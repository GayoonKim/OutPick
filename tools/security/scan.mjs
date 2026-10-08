import {spawnSync, execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync, mkdirSync, mkdtempSync, rmSync, existsSync, lstatSync} from 'node:fs';
import {resolve, join, dirname} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash, randomUUID} from 'node:crypto';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';

const sha = data => createHash('sha256').update(data).digest('hex');
export class ScanError extends Error {constructor(code) {super(code);this.code=code;}}
export function loadPolicy(root) {
  let bytes, policy;
  try {bytes=readFileSync(join(root,'.local/security-policy.json'));policy=JSON.parse(bytes);}
  catch {throw new ScanError('LOCAL_POLICY_REQUIRED');}
  if(policy.version!==1||!Array.isArray(policy.forbiddenValues)||!policy.forbiddenValues.length||
    policy.forbiddenValues.some(value=>typeof value!=='string'||value.length<8)||
    !Array.isArray(policy.allowedBinaryPrefixes)||policy.allowedBinaryPrefixes.some(prefix=>typeof prefix!=='string'||!prefix.endsWith('/')||prefix.includes('..')||prefix.length<12))throw new ScanError('INVALID_LOCAL_POLICY');
  return {...policy,sha256:sha(bytes)};
}
function loadTool(root) {
  let lock, binary;
  try {lock=JSON.parse(readFileSync(join(root,'tools/security/gitleaks-lock.json')));binary=join(root,'.local/tools/gitleaks');}
  catch {throw new ScanError('SCANNER_NOT_PREPARED');}
  if(!existsSync(binary)||sha(readFileSync(binary))!==lock.binarySha256)throw new ScanError('SCANNER_CHECKSUM_MISMATCH');
  const result=spawnSync(binary,['version'],{encoding:'utf8',timeout:10000});
  if(result.error||result.status!==0||result.stdout.trim()!==lock.version)throw new ScanError('SCANNER_VERSION_MISMATCH');
  return binary;
}
function git(root,args) {try{return execFileSync('git',args,{cwd:root,maxBuffer:64*1024*1024});}catch{throw new ScanError('GIT_INPUT_ERROR');}}
const forbiddenPath=path=>/(^|\/)(\.env(?:\.[^/]+)?|\.firebaserc|\.local|\.gitleaksignore)(?:\/|$)/.test(path)&&!/(^|\/)\.env\.example$/.test(path);
function entries(root,mode) {
  if(mode==='candidate')return git(root,['ls-files','-z','--cached','--others','--exclude-standard']).toString().split('\0').filter(Boolean).map(path=>({path}));
  if(mode==='index')return git(root,['ls-files','--stage','-z']).toString().split('\0').filter(Boolean).map(row=>{
    const match=/^(\d+) ([0-9a-f]+) (\d)\t([\s\S]+)$/.exec(row);
    if(!match||match[3]!=='0'||!['100644','100755'].includes(match[1]))throw new ScanError('UNMERGED_OR_NONREGULAR_INDEX');
    return {path:match[4],object:match[2]};
  });
  throw new ScanError('INVALID_SCAN_MODE');
}
function safePath(path) {if(path.startsWith('/')||path.split('/').some(part=>part==='..'||part==='')||path.includes('\0'))throw new ScanError('INVALID_GIT_PATH');}
export function scanRepository({root,mode='candidate',ref='HEAD',run=spawnSync}) {
  root=resolve(root);const policy=loadPolicy(root),binary=loadTool(root);
  const temporary=mkdtempSync(join(tmpdir(),'outpick-secret-scan-'));
  const report=join(temporary,'scanner.json');const snapshot=join(temporary,'snapshot');mkdirSync(snapshot);
  const findings=[];let count=0;
  try {
    if(mode==='history') {
      if(!/^[A-Za-z0-9][A-Za-z0-9_./-]*$/.test(ref))throw new ScanError('INVALID_HISTORY_REF');
      const commits=git(root,['rev-list',ref]).toString().trim().split('\n').filter(Boolean);
      if(!commits.length)throw new ScanError('EMPTY_HISTORY');
      for(const commit of commits) {
        const paths=git(root,['ls-tree','-rz','--name-only',commit]).toString().split('\0').filter(Boolean);
        for(const path of paths) {
          safePath(path);count++;
          if(forbiddenPath(path))findings.push({file:path,line:0,rule:'forbidden-path'});
          const bytes=git(root,['show',`${commit}:${path}`]);
          if(policy.forbiddenValues.some(value=>bytes.includes(Buffer.from(value))))findings.push({file:path,line:0,rule:'forbidden-operational-value'});
        }
      }
      if(!count)throw new ScanError('EMPTY_HISTORY_FILES');
    } else {
      const list=entries(root,mode);if(!list.length)throw new ScanError('EMPTY_SCAN_INPUT');
      const unique=new Set();
      for(const entry of list) {
        const path=entry.path;safePath(path);
        if(mode==='candidate') {
          let stat;try{stat=lstatSync(join(root,path));}catch(error){if(error.code==='ENOENT')continue;throw error;}
          if(!stat.isFile()||stat.isSymbolicLink())throw new ScanError('NONREGULAR_CANDIDATE');
        }
        if(unique.has(path))continue;unique.add(path);count++;
        if(forbiddenPath(path))findings.push({file:path,line:0,rule:'forbidden-path'});
        let bytes;
        if(entry.object)bytes=git(root,['cat-file','blob',entry.object]);
        else {const physical=join(root,path);if(!existsSync(physical))continue;if(!lstatSync(physical).isFile()||lstatSync(physical).isSymbolicLink())throw new ScanError('NONREGULAR_CANDIDATE');bytes=readFileSync(physical);}
        if(bytes.includes(0)&&!policy.allowedBinaryPrefixes.some(prefix=>path.startsWith(prefix)))throw new ScanError('UNREVIEWED_BINARY');
        if(policy.forbiddenValues.some(value=>bytes.includes(Buffer.from(value))))findings.push({file:path,line:0,rule:'forbidden-operational-value'});
        const destination=join(snapshot,path);mkdirSync(dirname(destination),{recursive:true});writeFileSync(destination,bytes,{mode:0o600});
      }
      if(!count)throw new ScanError('EMPTY_SCAN_INPUT');
    }
    const args=[mode==='history'?'git':'dir',mode==='history'?root:snapshot,'--config',join(root,'.gitleaks.toml'),
      '--gitleaks-ignore-path',temporary,'--ignore-gitleaks-allow','--redact=100','--no-banner','--no-color','--log-level','error',
      '--report-format','json','--report-path',report,'--timeout','120'];
    if(mode==='history')args.push(`--log-opts=${ref}`);
    const result=run(binary,args,{cwd:root,encoding:'utf8',timeout:130000,maxBuffer:16*1024*1024});
    if(result.error||result.signal||![0,1].includes(result.status)||!existsSync(report))throw new ScanError('SCANNER_EXECUTION_ERROR');
    let raw;try{raw=JSON.parse(readFileSync(report));}catch{throw new ScanError('SCANNER_REPORT_INVALID');}
    if(!Array.isArray(raw)||(result.status===1&&!raw.length))throw new ScanError('SCANNER_REPORT_INVALID');
    for(const item of raw)findings.push({file:String(item.File??'unknown'),line:Number(item.StartLine??0),rule:String(item.RuleID??'unknown')});
    if(loadPolicy(root).sha256!==policy.sha256)throw new ScanError('POLICY_CHANGED_DURING_SCAN');
    const record={version:1,mode,ref:mode==='history'?ref:null,files:count,policySha256:policy.sha256,verdict:findings.length?'failed':'passed',findings};
    const output=join(root,'output/security');mkdirSync(output,{recursive:true,mode:0o700});
    const path=join(output,`${randomUUID()}.json`);writeFileSync(path,JSON.stringify(record,null,2)+'\n',{mode:0o600});
    return {...record,report:path};
  } finally {rmSync(temporary,{recursive:true,force:true});}
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const {values}=parseArgs({options:{mode:{type:'string',default:'candidate'},ref:{type:'string',default:'HEAD'}}});
  try {const result=scanRepository({root:resolve(import.meta.dirname,'../..'),mode:values.mode,ref:values.ref});console.log(JSON.stringify({verdict:result.verdict,mode:result.mode,files:result.files,findings:result.findings.length,report:result.report}));process.exitCode=result.verdict==='passed'?0:1;}
  catch(error){console.error(JSON.stringify({verdict:'blocked',reason:error instanceof ScanError?error.code:'UNEXPECTED_SCAN_ERROR'}));process.exitCode=2;}
}
