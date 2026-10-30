#!/usr/bin/env python3
"""Run on MacBook after sourcing ~/Android/env.sh; serial cold-start evidence, no API calls."""
import os, pathlib, subprocess, sys, time
home = pathlib.Path.home()
out = home / 'Android/work/v012-evidence'
out.mkdir(exist_ok=True)
def run(args, **kw):
    return subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=kw.pop("timeout", 180), **kw)
version = sys.argv[1]
for api in map(int, sys.argv[2:]):
    name = {34:'paply34',37:'paply'}.get(api, f'paplyfix{api}')
    port = 5620 + (api-29)*2
    serial = f'emulator-{port}'
    image = home / f'Android/sdk/system-images/android-{api}/google_apis/arm64-v8a/package.xml'
    if api not in (34,37):
        deadline = time.time()+3600
        while not image.exists():
            if time.time()>deadline: raise RuntimeError(f'Image timeout {api}')
            time.sleep(10)
        config = pathlib.Path(os.environ['ANDROID_AVD_HOME']) / f'{name}.avd/config.ini'
        if not config.exists():
            p=run(['avdmanager','create','avd','-n',name,'-k',f'system-images;android-{api};google_apis;arm64-v8a','-d','pixel'],input='no\n')
            if p.returncode: raise RuntimeError(p.stdout)
        text=config.read_text()
        import re
        text=re.sub(r'hw.ramSize=.*','hw.ramSize=4096',text)
        config.write_text(text)
    if os.environ.get('PAPLY_WAIT_ORIGINAL') and api not in (30,34,37):
        deadline=time.time()+3600
        while True:
            busy=False
            for line in run(['adb','devices']).stdout.splitlines()[1:]:
                if line.startswith('emulator-') and name in run(['adb','-s',line.split()[0],'emu','avd','name']).stdout.splitlines(): busy=True
            if (out/f'{api}-0.1.1-fresh.xml').exists() and not busy: break
            if time.time()>deadline: raise RuntimeError('original matrix wait timeout')
            time.sleep(5)
    env=dict(os.environ,PAPLY_AVD=name,PAPLY_PORT=str(port))
    p=run([str(home/'Android/emu-start.sh')],env=env,timeout=420)
    print(p.stdout,flush=True)
    if p.returncode: raise RuntimeError('boot failed')
    def adb(*args): return run(['adb','-s',serial,*args])
    # The existing AVD may already be running on another port.
    for line in run(['adb','devices']).stdout.splitlines()[1:]:
        if line.startswith('emulator-'):
            candidate=line.split()[0]
            if name in run(['adb','-s',candidate,'emu','avd','name']).stdout.splitlines(): serial=candidate
    try:
        adb('uninstall','com.paply.android')
        apk=home/f'Desktop/Paply-Android/Paply-{version}.apk'
        if version=='0.1.2': apk=home/'Android/work/v012/app/build/outputs/apk/release/app-release.apk'
        installation=adb('install',str(apk))
        print(api,version,installation.stdout,flush=True)
        if installation.returncode: raise RuntimeError('APK installation failed')
        def launch(label):
            adb('shell','am','force-stop','com.paply.android'); adb('logcat','-c')
            result=adb('shell','am','start','-a','android.intent.action.MAIN','-c','android.intent.category.LAUNCHER','-n','com.paply.android/.MainActivity')
            (out/f'{api}-{version}-{label}-launch.txt').write_text(result.stdout)
            time.sleep(8)
            logs=adb('logcat','-d','-v','threadtime').stdout
            (out/f'{api}-{version}-{label}.log').write_text(logs)
            adb('shell','uiautomator','dump','/sdcard/paply.xml')
            xml=adb('shell','cat','/sdcard/paply.xml').stdout
            (out/f'{api}-{version}-{label}.xml').write_text(xml)
            if version=='0.1.2' and label!='old-before-update' and '<hierarchy' in xml:
                import xml.etree.ElementTree as ET
                tab=next((n for n in ET.fromstring(xml).iter('node') if n.get('text')=='Diktat'),None)
                if tab is not None:
                    x1,y1,x2,y2=map(int,re.findall(r'\d+',tab.get('bounds')))
                    adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2)); time.sleep(2)
                    adb('shell','uiautomator','dump','/sdcard/paply.xml')
                    xml=adb('shell','cat','/sdcard/paply.xml').stdout
                    (out/f'{api}-{version}-{label}-setup.xml').write_text(xml)
            pid=adb('shell','pidof','com.paply.android').stdout.strip()
            fatal='FATAL EXCEPTION' in logs and 'Process: com.paply.android' in logs
            print(api,version,label,'pid='+pid,'fatal='+str(fatal),'setup='+str('Mikro erlauben' in xml and 'Groq-Schlüssel' in xml),flush=True)
        launch('fresh')
        if version=='0.1.2' and not os.environ.get('PAPLY_SMOKE_ONLY'):
            for locale in ('de-DE','en-US'):
                adb('root'); adb('wait-for-device')
                adb('shell','setprop','persist.sys.locale',locale)
                adb('reboot'); adb('wait-for-device')
                deadline=time.time()+180
                while adb('shell','getprop','sys.boot_completed').stdout.strip()!='1':
                    if time.time()>deadline: raise RuntimeError('locale reboot timeout')
                    time.sleep(2)
                time.sleep(3)
                launch(locale)
            adb('shell','cmd','uimode','night','yes'); launch('dark')
            adb('shell','cmd','uimode','night','no')
            adb('shell','pm','disable-user','--user','0','com.google.android.gms'); launch('no-gms')
            adb('shell','pm','enable','com.google.android.gms')
            adb('uninstall','com.paply.android')
            adb('install',str(home/'Desktop/Paply-Android/Paply-0.1.1.apk'))
            launch('old-before-update')
            print(adb('install','-r',str(apk)).stdout,flush=True); launch('update')
    finally:
        adb('emu','kill')
        time.sleep(3)
