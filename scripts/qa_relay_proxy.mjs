// Test-only per-instance network shaping; never reads/decrypts business content.
import http from 'node:http';
import fs from 'node:fs';
import {createRequire} from 'node:module';
const require = createRequire(new URL('../services/relay/package.json', import.meta.url));
const {WebSocket, WebSocketServer} = require('ws');
const [portText, upstreamText, controlPath] = process.argv.slice(2);
const port = Number(portText), upstream = new URL(upstreamText);
if (!Number.isInteger(port) || port < 1024 || port > 65535 || upstream.protocol !== 'http:' || upstream.hostname !== '127.0.0.1' ||
    upstream.pathname !== '/' || upstream.search || upstream.username || !controlPath?.startsWith('/')) throw Error('Explicit loopback test endpoints required');
const sleep = ms => new Promise(r => setTimeout(r, ms));
function faults() {
  const f = JSON.parse(fs.readFileSync(controlPath, 'utf8'));
  if (!Number.isInteger(f.latencyMs) || f.latencyMs < 0 || f.latencyMs > 5000 ||
      !Number.isInteger(f.bytesPerSecond) || f.bytesPerSecond < 16384 || f.bytesPerSecond > 16777216 || typeof f.offline !== 'boolean') throw Error('Invalid test fault profile');
  return f;
}
const sessions = new Set();
const server = http.createServer(async(req, res) => {
  try {
    const f=faults(); if(f.offline){res.writeHead(503);res.end();return}
    let size=0;const chunks=[];
    for await(const chunk of req){size+=chunk.length;if(size>131072){res.writeHead(413);res.end();return}chunks.push(chunk)}
    await sleep(f.latencyMs);
    const request=http.request(new URL(req.url,upstream),{method:req.method,headers:{...req.headers,host:upstream.host}},response=>{
      res.writeHead(response.statusCode,response.headers);response.pipe(res);
    });
    request.setTimeout(20000,()=>request.destroy());request.on('error',()=>{if(!res.headersSent)res.writeHead(502);res.end()});request.end(Buffer.concat(chunks));
  }catch{if(!res.headersSent)res.writeHead(503);res.end()}
});
const wss = new WebSocketServer({noServer:true,maxPayload:524288,perMessageDeflate:false});
server.on('upgrade',(req,socket,head)=>{
  if(faults().offline){socket.destroy();return}
  const address=new URL(req.url,upstream);address.protocol='ws:';
  const back=new WebSocket(address,{headers:{Authorization:req.headers.authorization??''},maxPayload:524288,perMessageDeflate:false,handshakeTimeout:10000});
  let front=null;let early=[];let earlyBytes=0;
  const close=()=>{back.terminate();front?.terminate();sessions.delete(close)};sessions.add(close);
  function forward(target) {
    const queue=[];let bytes=0;let pumping=false;
    return async(data,binary)=>{
      if(bytes+data.length>8388608){close();return}
      queue.push([data,binary]);bytes+=data.length;if(pumping)return;pumping=true;
      try{while(queue.length){const [body,isBinary]=queue.shift();const f=faults();if(f.offline){close();break}
        await sleep(f.latencyMs+Math.ceil(body.length/f.bytesPerSecond*1000));bytes-=body.length;
        if(target.readyState!==WebSocket.OPEN){close();break}
        await new Promise((resolve,reject)=>target.send(body,{binary:isBinary},e=>e?reject(e):resolve()));
      }}catch{close()}finally{pumping=false}
    };
  }
  let toFront;
  back.on('message',(data,binary)=>{
    if(toFront){void toFront(data,binary)}else{earlyBytes+=data.length;if(earlyBytes>8388608)close();else early.push([data,binary])}
  });
  back.on('open',()=>wss.handleUpgrade(req,socket,head,ws=>{
    front=ws;toFront=forward(front);const toBack=forward(back);
    front.on('message',(data,binary)=>void toBack(data,binary));
    front.on('close',close);front.on('error',close);
    for(const message of early)void toFront(...message);early=[];
  }));
  back.on('close',close);back.on('error',()=>{socket.destroy();close()});socket.on('error',close);
});
const timer=setInterval(()=>{try{if(faults().offline)for(const close of [...sessions])close()}catch{for(const close of [...sessions])close()}},100);
server.listen(port,'127.0.0.1',()=>console.log(`QA proxy listening on 127.0.0.1:${port}; control file only; no payload logs`));
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>{clearInterval(timer);for(const close of [...sessions])close();server.close(()=>process.exit(0))});
