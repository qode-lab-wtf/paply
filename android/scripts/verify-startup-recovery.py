#!/usr/bin/env python3
"""MacBook-only debug fault injection: private DUMP receiver; no production test hook."""
import os, pathlib, subprocess, time, re, xml.etree.ElementTree as ET
home=pathlib.Path.home(); out=home/'Android/work/v012-evidence'
def run(*args):
    p=subprocess.run(args,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
    return p.stdout
def adb(*args): return run('adb','-s','emulator-5622',*args)
deadline=time.time()+900
while not (out/'30-0.1.2-update.xml').exists():
    if time.time()>deadline: raise RuntimeError('matrix wait timeout')
    time.sleep(5)
time.sleep(10)
os.environ.update(PAPLY_AVD='paplyfix30',PAPLY_PORT='5622')
print(run(str(home/'Android/emu-start.sh')),flush=True)
try:
    adb('uninstall','com.paply.android')
    print(adb('install',str(home/'Android/work/v012/app/build/outputs/apk/debug/app-debug.apk')),flush=True)
    print(adb('install','-r',str(home/'Android/work/v012/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk')),flush=True)
    result=adb('shell','am','instrument','-w','-e','class','com.paply.android.StartupCompatibilityDeviceTest','com.paply.android.test/androidx.test.runner.AndroidJUnitRunner')
    (out/'30-compatibility-test.txt').write_text(result); print(result,flush=True)
    assert 'OK (1 test)' in result
    adb('shell','am','start','-n','com.paply.android/.MainActivity'); time.sleep(5)
    adb('shell','am','broadcast','-n','com.paply.android/.DebugControlReceiver','--es','command','startup-failure-test')
    time.sleep(5)
    def snapshot(name):
        adb('shell','uiautomator','dump','/sdcard/recovery.xml')
        xml=adb('shell','cat','/sdcard/recovery.xml')
        (out/(name+'.xml')).write_text(xml)
        return xml
    def tap(xml,label):
        node=next(n for n in ET.fromstring(xml).iter('node') if n.get('text','').lower()==label.lower())
        x1,y1,x2,y2=map(int,re.findall(r'\d+',node.get('bounds')))
        adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2)); time.sleep(2)
    xml=snapshot('30-recovery')
    with (out/'30-recovery.png').open('wb') as f:
        subprocess.run(['adb','-s','emulator-5622','exec-out','screencap','-p'],stdout=f,check=True)
    assert 'fehlerbericht teilen' in xml.lower() and 'ProviderException' in xml
    assert 'PRIVATE_TEST_SENTINEL' not in xml
    tap(xml,'Fehlerbericht teilen')
    chooser=snapshot('30-share')
    assert 'android' in chooser and 'com.paply.android.StartupFailureActivity' not in adb('shell','dumpsys','activity','top').split('ACTIVITY')[-1]
    adb('shell','input','keyevent','4'); time.sleep(2)
    tap(snapshot('30-recovery-return'),'Erneut versuchen')
    time.sleep(7)
    assert 'Gedanken-Knopf einrichten' in snapshot('30-recovery-retry')
    print('PASS: API compatibility, isolated recovery, private report, chooser, retry',flush=True)
finally:
    adb('emu','kill')
    time.sleep(5)
