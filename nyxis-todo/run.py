#!/usr/bin/env python3
"""Nyxis Todo をローカル Supabase で動かす（serve）/ 実経路で確かめる（check）。

Nyxis のクローン（NYXIS_DIR、既定 ~/src/nyxis）の scripts/local-supabase.py --exec から呼ぶ:

    python3 ~/src/nyxis/scripts/local-supabase.py --exec python3 run.py serve
    python3 ~/src/nyxis/scripts/local-supabase.py --exec python3 run.py check

serve: DB `nyxis_todo`（無ければ作って initTodoDatabase）を使い、API を :8080、画面を :3000 で出す。
       データは再起動しても残る。Ctrl-C で止める（DB は消さない）。
check: 使い捨ての DB と Auth の使い捨てユーザー2人（alice / bob）で、本物の JWT・本物の DB を通して
       「自分の Todo は操作できる／他人の Todo は読めず・変えられず・DB も変わらない」を確かめ、後片付けする。
接続情報・鍵・JWT は表示しない。
"""
import http.client
import http.server
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
from urllib.parse import urlsplit, urlunsplit
import uuid

HERE = Path(__file__).resolve().parent
NYXIS = Path(os.environ.get('NYXIS_DIR', Path.home() / 'src/nyxis'))
sys.path.insert(0, str(NYXIS / 'scripts'))
sys.dont_write_bytecode = True
import nyxis_local  # noqa: E402

BIN = HERE / 'backend/.lake/build/bin'
ISSUER = 'https://localhost:55325/auth/v1'
API_PORT = int(os.environ.get('TODO_API_PORT', '8080'))
WEB_PORT = int(os.environ.get('TODO_WEB_PORT', '3000'))
ENV = nyxis_local.scrub_docker_env(os.environ.copy())


def sql(statement, database='postgres'):
    result = subprocess.run(
        ['docker', '--context', 'desktop-linux', 'exec', '-i', 'supabase_db_nyxis',
         'psql', '-X', '-U', 'postgres', '-d', database, '-At', '-v', 'ON_ERROR_STOP=1'],
        input=statement.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=ENV, timeout=30)
    if result.returncode:
        raise RuntimeError('SQL failed (diagnostics withheld)')
    return result.stdout.decode().strip()


def local_db_url(database):
    endpoint = urlsplit(os.environ.get('NYXIS_DATABASE_URL', ''))
    assert endpoint.hostname in ('127.0.0.1', 'localhost') and endpoint.port == 55322 \
        and endpoint.path == '/postgres', 'run via local-supabase.py --exec (local DB only)'
    return urlunsplit(endpoint._replace(path='/' + database))


def request(method, path, body=None, token=None):
    conn = http.client.HTTPConnection('127.0.0.1', API_PORT, timeout=10)
    try:
        headers = {'Authorization': 'Bearer ' + token} if token else {}
        if body is not None:
            headers['Content-Type'] = 'application/json'
        conn.request(method, path, None if body is None else json.dumps(body), headers)
        res = conn.getresponse()
        return res.status, res.read().decode()
    finally:
        conn.close()


class Backend:
    """DB の準備・JWKS の TLS 中継・todoServer の起動をまとめる。"""

    def __init__(self, database, fresh):
        self.database, self.fresh = database, fresh

    def __enter__(self):
        nyxis_local.require_free_port(API_PORT)
        env = ENV.copy()
        env['NYXIS_DATABASE_URL'] = local_db_url(self.database)
        env['NYXIS_SUPABASE_ISSUER'] = ISSUER
        env['NYXIS_CORS_ORIGINS'] = f'http://127.0.0.1:{WEB_PORT},http://localhost:{WEB_PORT}'
        exists = sql(f"SELECT 1 FROM pg_database WHERE datname = '{self.database}';") == '1'
        assert not (self.fresh and exists), 'fresh DB name collided'
        if not exists:
            sql(f'CREATE DATABASE "{self.database}";')
            self.created = True
            subprocess.run([str(BIN / 'initTodoDatabase')], env=env, check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        else:
            self.created = False
        self._tls = nyxis_local.tls_material('nyxis-todo-tls-')
        cert, key = self._tls.__enter__()
        self._relay = nyxis_local.tls_server(nyxis_local.relay_handler(nyxis_local.local_jwks), cert, key, port=55325)
        self._relay.__enter__()
        env['CURL_CA_BUNDLE'] = str(cert)  # 一時 CA はこの子プロセスだけが信頼する
        self.proc = subprocess.Popen([str(BIN / 'todoServer'), str(API_PORT)], env=env,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        nyxis_local.wait_ready(self.proc, lambda: request('GET', '/health')[0] == 200, 'todoServer')
        return self

    def __exit__(self, *exc):
        nyxis_local.stop(self.proc)
        self._relay.__exit__(*exc)
        self._tls.__exit__(*exc)
        if self.fresh and self.created:
            sql(f'DROP DATABASE "{self.database}";')

    def rows(self):
        return sql('SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY "_nyxis_id"), \'[]\') FROM public."Todo" t;',
                   self.database)


def serve_frontend():
    config = json.dumps({'apiUrl': f'http://127.0.0.1:{API_PORT}',
                         'supabaseUrl': nyxis_local.LOCAL_AUTH,
                         'anonKey': os.environ['NYXIS_SUPABASE_ANON_KEY']})  # anon key は公開してよい値

    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *a, **k):
            super().__init__(*a, directory=str(HERE / 'frontend'), **k)

        def log_message(self, *_):
            pass

        def do_GET(self):
            if self.path == '/config.js':
                body = f'window.TODO_CONFIG = {config};'.encode()
                self.send_response(200)
                self.send_header('Content-Type', 'text/javascript')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            super().do_GET()

    server = http.server.ThreadingHTTPServer(('127.0.0.1', WEB_PORT), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def serve():
    with Backend('nyxis_todo', fresh=False):
        web = serve_frontend()
        print(f'API:  http://127.0.0.1:{API_PORT}', flush=True)
        print(f'画面: http://127.0.0.1:{WEB_PORT}  （ログインのメールは http://127.0.0.1:55324 の Mailpit）', flush=True)
        print('Ctrl-C で停止（DB nyxis_todo は残る）', flush=True)
        try:
            threading.Event().wait()
        except KeyboardInterrupt:
            pass
        finally:
            web.shutdown()


def check():
    n = 0

    def expect(method, path, status, body=None, token=None):
        nonlocal n
        got, text = request(method, path, body, token)
        assert got == status, f'{method} {path}: {got} != {status} ({text[:80]})'
        n += 1
        return text

    with nyxis_local.auth_sessions(['alice', 'bob'], prefix='nyxis-todo-check-') as s, \
            Backend('nyxis_todo_check_' + uuid.uuid4().hex, fresh=True) as db:
        a, b = s['alice'], s['bob']
        for u in (a, b):
            expect('POST', f"/users/{u['id']}", 201, {'name': u['email']}, u['access_token'])
            expect('POST', f"/users/{u['id']}", 409, {'name': 'again'}, u['access_token'])
        # 他人の User 行は作れない・読めない
        expect('GET', f"/users/{a['id']}", 403, token=b['access_token'])
        expect('POST', f'/users/{uuid.uuid4()}', 403, {'name': 'x'}, a['access_token'])

        aid = json.loads(expect('POST', '/todos', 201, {'title': 'alice の Todo', 'owner': b['id']}, a['access_token']))['id']
        bid = json.loads(expect('POST', '/todos', 201, {'title': 'bob の秘密'}, b['access_token']))['id']
        assert aid != bid
        rows = json.loads(db.rows())
        owners = {r['_nyxis_id']: r['owner'] for r in rows}
        # 本文で owner を bob に偽っても、持ち主は JWT の主体（alice）
        assert owners[aid] == ['entity', [], 'User', a['id']] and owners[bid] == ['entity', [], 'User', b['id']], owners
        n += 1

        la = json.loads(expect('GET', '/todos', 200, token=a['access_token']))
        assert [t['id'] for t in la] == [aid], la
        lb = json.loads(expect('GET', '/todos', 200, token=b['access_token']))
        assert [t['id'] for t in lb] == [bid], lb
        assert expect('GET', '/todos', 200) == '[]'  # 匿名
        n += 1

        # 自分の Todo は操作できる
        expect('POST', f'/todos/{aid}/done', 204, token=a['access_token'])
        expect('PATCH', f'/todos/{aid}', 204, {'title': '名前を変えた'}, a['access_token'])
        got = json.loads(expect('GET', f'/todos/{aid}', 200, token=a['access_token']))
        assert got['title'] == '名前を変えた' and got['done'] is True, got

        # 他人（bob）・匿名・偽の JWT からは、alice の Todo に何もできず、DB も変わらない
        before = db.rows()
        for token in (b['access_token'], None, 'forged.jwt.token', a['access_token'][:-4] + 'AAAA'):
            expect('GET', f'/todos/{aid}', 403, token=token)
            expect('PATCH', f'/todos/{aid}', 403, {'title': '乗っ取り'}, token)
            expect('POST', f'/todos/{aid}/undone', 403, token=token)
            expect('DELETE', f'/todos/{aid}', 403, token=token)
        assert db.rows() == before, 'denied requests changed rows'
        n += 1

        # 別の接続で持ち主を bob に書き換えると、次のリクエストから判定が変わる（キャッシュで判定していない）
        sql(f'''UPDATE public."Todo" SET owner = '["entity",[],"User","{b['id']}"]' WHERE "_nyxis_id" = '{aid}';''',
            db.database)
        expect('GET', f'/todos/{aid}', 403, token=a['access_token'])
        expect('GET', f'/todos/{aid}', 200, token=b['access_token'])

        expect('DELETE', f'/todos/{bid}', 204, token=b['access_token'])
        expect('GET', f'/todos/{bid}', 403, token=b['access_token'])
        expect('POST', '/todos', 400, {'title': '  '}, a['access_token'])
    print(f'check: {n} checks passed（本物の Auth の JWT・本物の DB・todoServer の HTTP。使い捨ての DB とユーザーは削除済み）')


if __name__ == '__main__':
    mode = sys.argv[1] if len(sys.argv) > 1 else ''
    if mode == 'serve':
        serve()
    elif mode == 'check':
        check()
    else:
        raise SystemExit('usage: run.py serve|check')
