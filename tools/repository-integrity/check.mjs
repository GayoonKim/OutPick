import {readFileSync,lstatSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,join} from 'node:path';

const root=resolve(import.meta.dirname,'../..');
const path=process.argv[2];
if(!path||path.startsWith('/')||path.split('/').includes('..'))throw new Error('저장소 내부 manifest 경로가 필요합니다.');
const manifest=JSON.parse(readFileSync(join(root,path),'utf8'));
if(manifest.version!==1||!manifest.source||!Object.keys(manifest.files??{}).length)throw new Error('유효한 고정 사본 목록이 필요합니다.');
for(const [file,expected] of Object.entries(manifest.files)) {
  if(file.startsWith('/')||file.split('/').includes('..')||!/^[a-f0-9]{64}$/.test(expected))throw new Error('잘못된 사본 경로 또는 해시');
  const full=join(root,file);const info=lstatSync(full);
  if(!info.isFile()||info.isSymbolicLink())throw new Error(`일반 파일이 아닌 사본: ${file}`);
  if(createHash('sha256').update(readFileSync(full)).digest('hex')!==expected)throw new Error(`고정 사본 불일치: ${file}`);
}
console.log(JSON.stringify({manifest:path,files:Object.keys(manifest.files).length,verdict:'passed'}));
