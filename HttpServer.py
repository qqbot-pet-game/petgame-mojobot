#!/usr/bin/python
import socket
import signal
import errno
from time import sleep 

httpheader = '''\
HTTP/1.1 200 OK
Context-Type: text/html
Server: Python-slp version 1.0
Context-Length: '''

def HttpResponse(header, whtml):
    # f = file(whtml)
    # contxtlist = f.readlines()
    # context = ''.join(contxtlist)
    context = whtml
    response = "%s %d\n\n%s\n\n" % (header,len(context),context)
    return response

class HttpServer:
    def __init__(self, port, reply_content, buffer_size = 1024):
        self.port = port
        self.reply_content = reply_content
        self.buffer_size = buffer_size
        strHost = "127.0.0.1"
        HOST = strHost #socket.inet_pton(socket.AF_INET,strHost)
        PORT = port

        self.lisfd = socket.socket(socket.AF_INET,socket.SOCK_STREAM)
        self.lisfd.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.lisfd.bind((HOST, PORT))
        self.lisfd.listen(2)

        # signal.signal(signal.SIGINT,self.sigIntHander)

        self.runflag = True

    def sigIntHander(self, signo, frame):
        print '[HttpServer] get signo# ',signo
        self.runflag = False
        self.lisfd.shutdown(socket.SHUT_RD)

    def run(self, data_handler):
        while self.runflag:
            try:
                confd, addr = self.lisfd.accept()
            except socket.error as e:
                if e.errno == errno.EINTR:
                    print '[HttpServer] get a except EINTR'
                else:
                    raise
                continue

            if self.runflag == False:
                break;

            print "[HttpServer] connect by ",addr
            data = confd.recv(self.buffer_size)
            if not data:
                break
            data_handler(data)
            confd.send(HttpResponse(httpheader,self.reply_content))
            confd.close()
        else:
            print '[HttpServer] runflag#',self.runflag

if __name__ == "__main__":
    def data_handler(data):
        # print data.split('\n')[-1]
        print data
    server = HttpServer(30001, 'OK')
    server.run(data_handler)
