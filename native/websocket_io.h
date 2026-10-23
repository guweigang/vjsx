#ifndef VJSX_WEBSOCKET_IO_H
#define VJSX_WEBSOCKET_IO_H
#include <openssl/ssl.h>
#include <openssl/x509v3.h>
#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#define vjsx_ws_close closesocket
static void vjsx_ws_nonblock(int fd) { u_long yes=1; ioctlsocket(fd,FIONBIO,&yes); }
static int vjsx_ws_pair(int *fds) {
 SOCKET l=socket(AF_INET,SOCK_STREAM,0), a=INVALID_SOCKET,b=INVALID_SOCKET;
 struct sockaddr_in sa={0}; int len=sizeof(sa); sa.sin_family=AF_INET; sa.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
 if(bind(l,(void*)&sa,len)||listen(l,1)||getsockname(l,(void*)&sa,&len)) goto fail;
 a=socket(AF_INET,SOCK_STREAM,0); if(connect(a,(void*)&sa,len)) goto fail;
 b=accept(l,0,0); if(b==INVALID_SOCKET) goto fail;
 closesocket(l); fds[0]=(int)a; fds[1]=(int)b; vjsx_ws_nonblock(fds[0]); vjsx_ws_nonblock(fds[1]); return 0;
 fail: closesocket(l); if(a!=INVALID_SOCKET) closesocket(a); if(b!=INVALID_SOCKET) closesocket(b); return -1;
}
#else
#include <sys/socket.h>
#include <arpa/inet.h>
#include <sys/select.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#define vjsx_ws_close close
static void vjsx_ws_nonblock(int fd) { fcntl(fd,F_SETFL,fcntl(fd,F_GETFL,0)|O_NONBLOCK); }
static int vjsx_ws_pair(int *fds) {
 if(socketpair(AF_UNIX,SOCK_STREAM,0,fds)) return -1;
 vjsx_ws_nonblock(fds[0]); vjsx_ws_nonblock(fds[1]); return 0;
}
#endif
static void vjsx_ws_signal(int fd) {
 char b=1;
#ifdef MSG_NOSIGNAL
 send(fd,&b,1,MSG_NOSIGNAL);
#else
 send(fd,&b,1,0);
#endif
}
static void vjsx_ws_drain(int fd) { char buf[256]; while(recv(fd,buf,sizeof(buf),0)>0) {} }
/* A blocking readiness wait, interrupted by the command socket. No timer polling. */
static int vjsx_ws_wait(int fd,int wake,int writing,int timeout_ms) {
 if(wake<0) return -1;
#ifndef _WIN32
 if(wake>=FD_SETSIZE || fd>=FD_SETSIZE) return -1;
#endif
 fd_set r,w; FD_ZERO(&r); FD_ZERO(&w); FD_SET(wake,&r);
 if(fd>=0) { if(writing) FD_SET(fd,&w); else FD_SET(fd,&r); }
 struct timeval tv={timeout_ms/1000,(timeout_ms%1000)*1000};
 int n=select((fd>wake?fd:wake)+1,&r,&w,0,timeout_ms<0?0:&tv);
 if(n<0) {
#ifndef _WIN32
 if(errno==EINTR) return 4;
#endif
 return -1;
 }
 if(!n) return 0;
 return (FD_ISSET(wake,&r)?2:0)|((fd>=0&&(FD_ISSET(fd,&r)||FD_ISSET(fd,&w)))?1:0);
}
static int vjsx_ws_plain_io(int fd,void *buf,int len,int writing) {
 int n;
 if(writing) {
#ifdef SO_NOSIGPIPE
  int yes=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,(void*)&yes,sizeof(yes));
#endif
#ifdef MSG_NOSIGNAL
  n=(int)send(fd,buf,len,MSG_NOSIGNAL);
#else
  n=(int)send(fd,buf,len,0);
#endif
 } else n=(int)recv(fd,buf,len,0);
 if(n>=0) return n;
#ifdef _WIN32
 int error=WSAGetLastError();
 return (error==WSAEWOULDBLOCK || error==WSAEINTR) ? -2 : -1;
#else
 return (errno==EAGAIN || errno==EWOULDBLOCK || errno==EINTR) ? -2 : -1;
#endif
}
static int vjsx_ws_connect_start(int fd, const void *addr, unsigned int len) {
 if(connect(fd,addr,len)==0) return 0;
#ifdef _WIN32
 return WSAGetLastError()==WSAEWOULDBLOCK ? 1 : -1;
#else
 return (errno==EINPROGRESS || errno==EAGAIN || errno==EINTR) ? 1 : -1;
#endif
}
static int vjsx_ws_connect_status(int fd) {
 int error=0;
#ifdef _WIN32
 int len=sizeof(error);
#else
 socklen_t len=sizeof(error);
#endif
 if(getsockopt(fd,SOL_SOCKET,SO_ERROR,(void*)&error,&len)) return -1;
 return error;
}
static int vjsx_ws_tls_start(SSL *ssl,int fd,const char *host) {
 return SSL_set_fd(ssl,fd)==1 && SSL_set_tlsext_host_name(ssl,host)==1;
}
static int vjsx_ws_tls_identity(SSL *ssl,const char *host) {
 unsigned char buf[16];
 X509_VERIFY_PARAM *p=SSL_get0_param(ssl);
 X509_VERIFY_PARAM_set_hostflags(p,X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS);
 if(inet_pton(AF_INET,host,buf)==1||inet_pton(AF_INET6,host,buf)==1)
   return X509_VERIFY_PARAM_set1_ip_asc(p,host);
 return SSL_set1_host(ssl,host);
}
#endif
