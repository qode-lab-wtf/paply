// Move the selected runtime into the test app's own support folder. No network.
// APFS clones keep an independent file identity without duplicating model blocks.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {execFileSync}=require('node:child_process');
const {atomicJson}=require('../meeting/local-files');
const input=path.resolve(process.argv[2] || '../work/local-runtime.json');
const destination=path.resolve(process.argv[3] || path.join(os.homedir(),'Library/Application Support/Paply Gespräch Test/runtime'));
const config=JSON.parse(fs.readFileSync(input,'utf8'));
fs.mkdirSync(destination,{recursive:true});
function clone(source,target){
  if(fs.existsSync(target))return;
  fs.mkdirSync(path.dirname(target),{recursive:true});
  const temp=target+'.partial-'+process.pid;
  execFileSync('/bin/cp',['-cR',source,temp]);fs.renameSync(temp,target);
}
const pythonBase=execFileSync(config.asrPython,['-c','import sys;print(sys.base_prefix)'],{encoding:'utf8'}).trim();
const diarBase=execFileSync(config.diarizationPython,['-c','import sys;print(sys.base_prefix)'],{encoding:'utf8'}).trim();
if(pythonBase!==diarBase)throw new Error('Runtime preparation requires the same pinned base Python');
const base=path.join(destination,'python-base-3.12.13');clone(pythonBase,base);
const pythonRuntimes=[['asrPython',config.asrBackend === 'faster-whisper' ? 'asr-faster-whisper-1.2.1' : 'asr-python'],['diarizationPython','diarization-python'],...(config.enhancementPython ? [['enhancementPython','enhancement-clearvoice-0.1.2']] : [])];
for(const [key,folder] of pythonRuntimes){
  const actualBase=execFileSync(config[key],['-c','import sys;print(sys.base_prefix)'],{encoding:'utf8'}).trim();
  if(actualBase!==pythonBase)throw new Error('Runtime preparation requires the same pinned base Python');
  const venv=path.join(destination,folder);clone(path.dirname(path.dirname(config[key])),venv);
  const cfg=path.join(venv,'pyvenv.cfg');fs.writeFileSync(cfg,fs.readFileSync(cfg,'utf8').replace(/^home = .*$/m,'home = '+path.join(base,'bin')));
  const python=path.join(venv,'bin/python');if(fs.lstatSync(python).isSymbolicLink())fs.unlinkSync(python);
  if(!fs.existsSync(python))fs.symlinkSync(path.join(base,'bin/python3.12'),python);
  config[key]=python;
}
for(const [key,folder] of [['whisperModel','whisper-'+config.models.whisperRevision],['pyannoteModel','pyannote-'+config.models.pyannoteRevision],...(config.fasterWhisperModel ? [['fasterWhisperModel','faster-whisper-'+config.models.fasterWhisperRevision]] : []),...(config.enhancementModel ? [['enhancementModel','mossformer-'+config.models.enhancementRevision]] : [])]){
  const target=path.join(destination,'models',folder);clone(config[key],target);config[key]=target;
}
if(config.fluidBinary){const target=path.join(destination,'fluidaudio','fluidaudiocli');clone(config.fluidBinary,target);config.fluidBinary=target;}
if(config.reporter){
  const reporter=config.reporter;
  const binary=path.join(destination,'ollama-0.34.2');clone(path.dirname(reporter.binary),binary);reporter.binary=path.join(binary,'ollama');
  const [model,tag]=reporter.model.split(':');
  if(!/^[a-zA-Z0-9._-]+$/.test(model)||!/^[a-zA-Z0-9._-]+$/.test(tag))throw new Error('Invalid local model name');
  const manifestPath=path.join('manifests','registry.ollama.ai','library',model,tag);
  const manifest=JSON.parse(fs.readFileSync(path.join(reporter.modelsPath,manifestPath),'utf8'));
  const models=path.join(destination,'report-models');
  clone(path.join(reporter.modelsPath,manifestPath),path.join(models,manifestPath));
  for(const entry of [manifest.config,...manifest.layers]){
    if(!/^sha256:[0-9a-f]{64}$/.test(entry.digest))throw new Error('Invalid model artifact digest');
    const filename=path.join('blobs',entry.digest.replace(':','-'));clone(path.join(reporter.modelsPath,filename),path.join(models,filename));
  }
  reporter.modelsPath=models;
}
for(const [key] of pythonRuntimes)execFileSync(config[key],['-c','import sys; assert sys.base_prefix.startswith('+JSON.stringify(destination)+')']);
atomicJson(path.join(destination,'runtime.json'),config);
console.log(path.join(destination,'runtime.json'));
