import http from 'node:http';
import fs from 'node:fs';
const server=http.createServer(async(req,res)=>{
 if(req.url==='/stop'){res.end('bye');setTimeout(()=>{server.closeAllConnections();server.close(()=>console.log('CLOSED'));},25);return;}
 let body='';for await(const part of req)body+=new TextDecoder().decode(part);
 res.setHeader('X-Test','native-v');res.end(JSON.stringify({method:req.method,url:req.url,body}));
});
server.on('upgrade',(req,socket,head)=>{
 if(req.url==='/raw') { socket.write('HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: native-echo\r\n\r\n'); if(head.length)socket.write(head);socket.on('data',data=>socket.write(data));return; }
 if(req.url!=='/ws')return socket.destroy();
 const ws=socket.acceptWebSocket();ws.on('message',(data,binary)=>{if(!binary && data.toString()==='please-close')ws.close(3000,'done');else ws.send(binary?data:'echo:'+data.toString());});
});
server.listen(0,'127.0.0.1',()=>{fs.writeFileSync(process.argv[1],JSON.stringify(server.address()));console.log('LISTENING');});
