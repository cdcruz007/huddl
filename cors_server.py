import http.server
import socketserver
import os

class CORSHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('X-Frame-Options', 'ALLOWALL')
        self.send_header('Content-Security-Policy', 'frame-ancestors *')
        super().end_headers()

class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

os.chdir('/home/user/flutter_app/build/web')
print('Serving on port 5060...')
with ReusableTCPServer(('0.0.0.0', 5060), CORSHandler) as httpd:
    httpd.serve_forever()
