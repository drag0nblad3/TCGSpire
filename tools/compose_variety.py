"""Render eight original 16-bar electronic cues. Requires numpy and FFmpeg.
Run from repository root: python tools/compose_variety.py
All instruments synthesized here; no sampled recordings or gameplay RNG.
"""
from pathlib import Path
import subprocess, tempfile, wave
import numpy as np
RATE = 22050
# Mood, title, tempo, MIDI roots, melody degrees, timbre, rhythmic style.
SCORES = [
 ('menu_afterhours','After Hours',78,[45,41,48,43],[7,4,2,0,4,7,9,4],'bell','sparse'),
 ('menu_glass','Glass Skyline',92,[48,44,51,46],[0,7,3,10,7,5,3,2],'keys','broken'),
 ('map_rain','Rain on the Relay',96,[40,43,38,45],[0,2,7,4,9,7,2,4],'keys','shuffle'),
 ('map_drift','Carrier Drift',108,[42,38,45,40],[7,0,3,5,10,7,5,3],'bell','sync'),
 ('combat_voltage','Voltage Runner',126,[38,41,34,36],[0,7,12,10,7,3,5,2],'acid','drive'),
 ('combat_ghost','Ghost Protocol',112,[45,41,43,40],[0,3,7,10,12,7,5,3],'keys','break'),
 ('boss_lockdown','Lockdown',138,[36,37,32,31],[0,1,7,12,6,7,1,0],'acid','industrial'),
 ('boss_blackout','Blackout Engine',104,[42,38,35,37],[0,7,10,3,12,10,7,5],'bell','half'),
]

def render(spec):
    name,title,bpm,roots,melody,timbre,style=spec
    n=round(64*60/bpm*RATE); beat=n/RATE/64
    mix=np.zeros(n); rng=np.random.default_rng(2301+sum(map(ord,name)))
    def add(start,x,gain):
        indices=(round(start*RATE)+np.arange(len(x)))%n
        np.add.at(mix,indices,x*gain)
    def note(start,duration,midi,gain,kind):
        t=np.arange(round(duration*RATE))/RATE; u=t/duration
        f=440*2**((midi-69)/12); p=2*np.pi*f*t
        env=np.minimum(t/.008,1)*(1-u)**2
        if kind=='pad':
            env=np.sin(np.pi*u)**2
            x=.65*np.sin(p)+.25*np.sin(p*1.002)+.1*np.sin(p*2)
        elif kind=='bass': x=.8*np.sin(p)+.15*np.sin(2*p)+.05*np.sin(3*p)
        elif kind=='bell': x=np.sin(p+2*np.sin(p*2.7)*np.exp(-t*7))
        elif kind=='acid': x=np.tanh(2*(np.sin(p)+.3*np.sin(2*p)*np.exp(-t*14)))*.8
        else: x=.7*np.sin(p)+.2*np.sin(2*p)*np.exp(-t*8)+.1*np.sin(3*p)*np.exp(-t*15)
        add(start,x*env,gain)
    def drum(start,kind,gain):
        d={'kick':.26,'snare':.18,'hat':.065,'metal':.28}[kind]
        t=np.arange(round(d*RATE))/RATE; env=np.minimum(t/.002,1)*(1-t/d)**3
        noise=rng.uniform(-1,1,len(t)); noise=(noise-np.roll(noise,1))*.5
        if kind=='kick': x=np.sin(2*np.pi*(43*t+6*(1-np.exp(-28*t))))
        elif kind=='snare': x=.8*noise+.2*np.sin(2*np.pi*190*t)
        elif kind=='metal': x=.5*noise+.25*np.sin(2*np.pi*713*t)+.25*np.sin(2*np.pi*1173*t)
        else: x=noise
        add(start,x*env,gain)
    for bar in range(16):
        root=roots[(bar//2)%4]; base=bar*4*beat
        # Thin the middle section, add octave answers in the last phrase.
        thin=8<=bar<12; loud=name.startswith(('combat','boss'))
        chord=[0,3,7,10] if style not in ('industrial','half') else [0,7,12,13]
        for degree in chord: note(base,4.4*beat,root+12+degree,.016,'pad')
        bass_steps=[0,3,6] if style in ('sync','shuffle','break') else [0,2,4,6]
        if style in ('half','sparse'): bass_steps=[0,5]
        for step in bass_steps:
            note(base+step*.5*beat,beat*.5,root-12 if root>=40 else root,.1,'bass')
        for step in range(8):
            if (thin or style=='sparse') and step%2: continue
            swing=.08 if style in ('shuffle','broken') and step%2 else 0
            at=base+(step*.5+swing)*beat
            degree=melody[(step+bar%2*2)%len(melody)]
            midi=root+12+degree+(12 if bar>=12 and step in (3,7) else 0)
            note(at,beat*.65,midi,.035 if thin else .048,timbre)
            note(at+beat*.75,beat*.65,midi,.012,timbre)
        if style=='sparse': continue
        for step in range(8 if style!='industrial' else 16):
            if thin and step%2: continue
            drum(base+step*beat*(.25 if style=='industrial' else .5),'hat',.025 if step%2 else .018)
        kicks=[0,1.5,2.75] if style in ('break','broken','sync') else [0,2]
        if style in ('drive','industrial'): kicks=[0,1,2,3]
        if style=='half': kicks=[0,1.75]
        for step in kicks: drum(base+step*beat,'kick',.19 if loud else .11)
        for step in ([2] if style=='half' else [1,3]):
            if loud or (bar%2==1 and not thin): drum(base+step*beat,'snare',.09 if loud else .045)
        if bar%4==3 and loud:
            for step in [3.5,3.75]: drum(base+step*beat,'metal' if style=='industrial' else 'snare',.04)
    mix=np.tanh(mix*1.3)*.73
    assert np.max(np.abs(mix))<.9 and np.sqrt(np.mean(mix**2))>.01
    assert abs(mix[0]-mix[-1])<.04, name+' loop seam'
    pcm=(mix*32767).astype('<i2')
    with tempfile.NamedTemporaryFile(suffix='.wav') as tmp:
        with wave.open(tmp.name,'wb') as wav:
            wav.setparams((1,2,RATE,0,'NONE','not compressed')); wav.writeframes(pcm.tobytes())
        out=Path('assets/music')/(name+'.ogg')
        subprocess.run(['ffmpeg','-v','error','-y','-i',tmp.name,'-c:a','libvorbis','-q:a','2','-metadata','title='+title,str(out)],check=True)
    print(f'{title}: {n/RATE:.1f}s, {out.stat().st_size//1024} KB, peak {np.max(np.abs(mix)):.3f}')

if __name__=='__main__':
    for score in SCORES: render(score)
