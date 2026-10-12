const fs = require('fs'), path = require('path'), net = require('net');
const root = 'P:/Deepdraft';
const files = fs.readdirSync(root+'/scripts',{recursive:true}).filter(p=>p.endsWith('.gd')&&!p.startsWith('tests')).map(p=>path.join(root,'scripts',p));
files.push(root+'/scripts/tests/DwarfRestTest.gd');
const wanted = new Set(files.map(p=>('file:///'+p.replaceAll('\\','/')).toLowerCase()));
const got = new Map(), seen = []; let buffer = Buffer.alloc(0), started = false;
const sock = net.connect(6017,'127.0.0.1');
function send(value) { const body = Buffer.from(JSON.stringify(value)); sock.write(`Content-Length: ${body.length}\r\n\r\n`); sock.write(body); }
function finish() { console.log(JSON.stringify({requested:wanted.size,received:got.size,seen,diagnostics:[...got].flatMap(([uri,diagnostics])=>diagnostics.map(d=>({uri,...d})))})); sock.destroy(); process.exit(got.size===wanted.size?0:1); }
setTimeout(finish,45000);
sock.on('connect',()=>send({jsonrpc:'2.0',id:1,method:'initialize',params:{processId:null,rootUri:'file:///P:/Deepdraft',capabilities:{}}}));
sock.on('data',data=>{ buffer=Buffer.concat([buffer,data]); while(true) {
 const h=buffer.indexOf('\r\n\r\n'); if(h<0)break;
 const n=Number(/Content-Length: (\d+)/i.exec(buffer.subarray(0,h).toString())[1]); if(buffer.length<h+4+n)break;
 const msg=JSON.parse(buffer.subarray(h+4,h+4+n)); buffer=buffer.subarray(h+4+n);
 if(msg.id===1&&!started){started=true;send({jsonrpc:'2.0',method:'initialized',params:{}});for(const p of files)send({jsonrpc:'2.0',method:'textDocument/didOpen',params:{textDocument:{uri:'file:///'+p.replaceAll('\\','/'),languageId:'gdscript',version:1,text:fs.readFileSync(p,'utf8')}}});}
 if(seen.length<4)seen.push(msg.method||msg.id);
 if(msg.method==='textDocument/publishDiagnostics'){const uri=decodeURIComponent(msg.params.uri).toLowerCase();if(wanted.has(uri)){got.set(uri,msg.params.diagnostics);if(got.size===wanted.size)setTimeout(finish,500);}else if(seen.length<8)seen.push(msg.params.uri);}
 }});
sock.on('error',e=>{console.error(e.message);process.exit(1)});




