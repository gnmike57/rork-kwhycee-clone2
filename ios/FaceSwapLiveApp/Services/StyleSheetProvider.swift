import Foundation
import UIKit

nonisolated enum StyleSheetProvider {
    /// Install-time stealth configuration for the injected patch script.
    ///
    /// Defaults reproduce the original behaviour exactly: capture inputs are auto-filled,
    /// the `files` fallback stays available, and wrapper functions are left unmasked.
    nonisolated struct StealthOptions: Sendable, Equatable {
        var nativePickerMode: Bool = false
        /// `auto`, `picker` or `native` — only consulted while `nativePickerMode` is on.
        var captureButtonPolicy: String = "auto"
        var accessorHardening: Bool = false
        var maskWrappersAsNative: Bool = false

        static let `default` = StealthOptions()
    }

    // The disguise state is no longer reachable through a predictable key. Two
    // random per-process tokens: one is baked into the Symbol.for registry key
    // (so only scripts built in this process can look the handle up at all) and
    // the other is required by the guard function before it answers. A page that
    // enumerates window symbols finds only the guard, and `Symbol.keyFor` leaks
    // nothing useful — the secret the guard wants is never the key it sits under.
    nonisolated static let fslStateKeySuffix: String = String(UUID().uuidString.lowercased().prefix(16))
    nonisolated static let fslStateToken: String = String(UUID().uuidString.lowercased().prefix(24))

    /// JS expression that resolves to the page-side disguise state object.
    nonisolated static var fslStateAccessorJS: String {
        "window[Symbol.for('fsl\(fslStateKeySuffix)')]('\(fslStateToken)')"
    }

    static var patchScript: String { patchScript(stealth: .default) }

    static func patchScript(stealth: StealthOptions) -> String {
        let nativePicker = stealth.nativePickerMode ? "true" : "false"
        let hardening = stealth.accessorHardening ? "true" : "false"
        let mask = stealth.maskWrappersAsNative ? "true" : "false"
        let policy = stealth.captureButtonPolicy
        return patchScriptBody
            .replacingOccurrences(of: "__FSL_NP__", with: nativePicker)
            .replacingOccurrences(of: "__FSL_HARD__", with: hardening)
            .replacingOccurrences(of: "__FSL_MASK__", with: mask)
            .replacingOccurrences(of: "__FSL_CAPMODE__", with: policy)
            .replacingOccurrences(of: "__FSL_KEY__", with: fslStateKeySuffix)
            .replacingOccurrences(of: "__FSL_TOKEN__", with: fslStateToken)
    }

    private static let patchScriptBody: String = """
    (function(){
    'use strict';
    try{
    if(window[Symbol.for('fsl__FSL_KEY__')])return;

    try{
        if(typeof navigator.standalone==='undefined'){
            Object.defineProperty(navigator,'standalone',{get:function(){return false;},configurable:true,enumerable:true});
        }
    }catch(e){}

    try{
        if(!window.safari){
            window.safari={pushNotification:{permission:function(){return'default';},requestPermission:function(u,c){if(c)c('default');}}};
        }
    }catch(e){}

    var md=navigator.mediaDevices;
    if(!md||typeof MediaDevices==='undefined')return;

    var origEnum=MediaDevices.prototype.enumerateDevices;
    var origGUM=MediaDevices.prototype.getUserMedia;

    var _s=Object.create(null);
    _s.a=false;
    _s.ra=true;
    _s.is=null;
    _s.vs=null;
    _s.fis=null;
    _s.fvs=null;
    _s.bis=null;
    _s.bvs=null;
    _s.fseq=[];
    _s.bseq=[];
    _s.fi=0;
    _s.bi=0;
    _s.adv='request';
    _s.defFacing='user';
    _s._c=null;
    _s._x=null;
    _s._cf=null;
    _s._xf=null;
    _s._cb=null;
    _s._xb=null;
    _s._st=null;
    _s._ve=null;
    _s._ri=null;
    _s._lv=null;
    _s._fx=null;
    _s._fxc=null;
    // Marks one force re-inject, so a slow rebuild that lands after a newer
    // press or a switch-off is dropped instead of overwriting the feed.
    _s._rin=0;
    _s.fp=null;
    _s.bp=null;
    _s.mp=null;
    _s.np=__FSL_NP__;
    _s.capMode='__FSL_CAPMODE__';
    _s.hard=__FSL_HARD__;
    _s.mask=__FSL_MASK__;

    // Device-matched media layer. Every field below stays inert until the
    // behaviour script switches it on, so the default path is byte-identical.
    _s.mo=false;
    _s.mok=1;
    _s.grain=false;
    _s.jit=false;
    _s.skin=false;
    _s.expo=false;
    _s.frz=false;
    _s.pr=false;
    _s.prf=false;
    _s.prsec=20;
    _s.cap=false;
    _s.caplim=null;
    _s.auditList=null;
    _s.auditMics=null;
    _s.auditMic=null;
    _s._req=null;
    // Whether a camera has been granted yet. A real phone answers the device
    // list very differently either side of this.
    _s.gr=false;
    // Mixed with the site's own name to produce this site's identifiers.
    _s.idsec='';
    _s.rep=false;
    _s.crop=false;
    _s.onepass=false;
    // Per-still framing, kept apart for each frame shape: a still framed for a
    // widescreen ask is framed wrongly for a 4:3 one. An empty map is the
    // untouched cover-fit for every shape, which is what the old single
    // identity crop was.
    _s.fc={};
    _s.fc2={};
    _s.bc={};
    _s.bc2={};
    // Live zoom for a running video feed. Stills keep theirs in the maps above;
    // a clip takes it live and forgets it when the feed changes.
    _s.lzf=1;
    _s.lzb=1;
    // Camera and microphone are separate grants, as on a real phone: asking
    // for video never opens the microphone.
    _s.grm=false;
    // Monotonic capture counter for IMG_ names. Starts anywhere, only rises.
    _s.imgSeq=0;

    var _sk=Symbol.for('fsl__FSL_KEY__');
    var _tok='__FSL_TOKEN__';
    // A guard function, not the state. Enumerating symbols on window finds this
    // function; calling it without the token answers null, and its source shows
    // only a reference to a closure variable, never the token value.
    var _guard=function(k){return k===_tok?_s:null;};
    Object.defineProperty(window,_sk,{value:_guard,writable:false,configurable:false,enumerable:false});

    function gs(){return _s;}

    function nowMs(){return (window.performance&&performance.now)?performance.now():Date.now();}

    // ---- Making a replacement sit where a built-in sits -------------------
    // A real built-in carries no own toString and no marker property of any
    // kind, so both live off to the side instead: one patched
    // Function.prototype.toString, and sets keyed by the object itself. Nothing
    // is written onto a function or onto a host object where a page could read
    // it back. The toString patch installs only on first real use, so with
    // every switch off it is never installed at all.
    var _nat=new WeakSet();
    var _natName=new WeakMap();
    var _seen=new WeakSet();
    var _tsReady=false;

    function ensureNativeToString(){
        if(_tsReady)return;
        _tsReady=true;
        try{
            var origTS=Function.prototype.toString;
            var patched=function toString(){
                try{
                    if(_nat.has(this)){
                        var n=_natName.get(this);
                        if(n===undefined||n===null)n=this.name||'';
                        // JavaScriptCore's own wording, indent included. The
                        // escapes are doubled because this file's Swift literal
                        // processes them before the page ever sees the text.
                        return 'function '+n+'() {\\n    [native code]\\n}';
                    }
                }catch(e){}
                return origTS.call(this);
            };
            Function.prototype.toString=patched;
            _nat.add(patched);
            _natName.set(patched,'toString');
        }catch(e){}
    }

    function asNative(fn,name){
        try{
            if(typeof fn!=='function')return fn;
            ensureNativeToString();
            if(name)Object.defineProperty(fn,'name',{value:name,configurable:true});
            _nat.add(fn);
            _natName.set(fn,name||fn.name||'');
        }catch(e){}
        return fn;
    }

    // True the first time an object is handed in, false after. Replaces the
    // marker properties a page could otherwise read straight off a prototype.
    function firstTouch(obj){
        try{
            if(!obj)return false;
            if(_seen.has(obj))return false;
            _seen.add(obj);
            return true;
        }catch(e){return true;}
    }

    _s._asNative=asNative;
    _s._firstTouch=firstTouch;

    // ---- Per-feed answers, held where a real feed holds them ---------------
    // A real live feed carries no own properties at all: its name is an accessor
    // on the shared prototype and its describe-yourself calls are methods there
    // too. Putting them on the feed itself is visible to any page that asks the
    // feed for its own property names, so the answers live in a side table and
    // the prototype is consulted once.
    var _tinfo=new WeakMap();
    var _tproto=false;

    function trackInfo(track){
        var i=_tinfo.get(track);
        if(!i){i={};_tinfo.set(track,i);}
        return i;
    }

    function ensureTrackProto(){
        if(_tproto)return;
        _tproto=true;
        try{
            var TP=(window.MediaStreamTrack&&MediaStreamTrack.prototype)||null;
            if(!TP)return;
            var dl=Object.getOwnPropertyDescriptor(TP,'label');
            if(dl&&dl.get){
                var oLabel=dl.get;
                Object.defineProperty(TP,'label',{
                    get:maskNative(function(){
                        try{
                            var i=_tinfo.get(this);
                            if(i&&typeof i.label==='string')return i.label;
                        }catch(e){}
                        return oLabel.call(this);
                    },'get label'),
                    set:undefined,configurable:true,enumerable:true
                });
            }
            var di=Object.getOwnPropertyDescriptor(TP,'id');
            if(di&&di.get){
                var oId=di.get;
                Object.defineProperty(TP,'id',{
                    get:maskNative(function(){
                        try{
                            var i=_tinfo.get(this);
                            if(i&&typeof i.id==='string')return i.id;
                        }catch(e){}
                        return oId.call(this);
                    },'get id'),
                    set:undefined,configurable:true,enumerable:true
                });
            }
            var oGS=TP.getSettings;
            if(typeof oGS==='function'){
                TP.getSettings=maskNative(function getSettings(){
                    var base=oGS.call(this);
                    try{
                        var i=_tinfo.get(this);
                        if(i&&i.settings)return i.settings(base);
                    }catch(e){}
                    return base;
                },'getSettings');
            }
            var oGC=TP.getCapabilities;
            if(typeof oGC==='function'){
                TP.getCapabilities=maskNative(function getCapabilities(){
                    var base=oGC.call(this);
                    try{
                        var i=_tinfo.get(this);
                        if(i&&i.caps)return i.caps(base);
                    }catch(e){}
                    return base;
                },'getCapabilities');
            }
            var oStop=TP.stop;
            if(typeof oStop==='function'){
                TP.stop=maskNative(function stop(){
                    var r=oStop.apply(this,arguments);
                    try{
                        var i=_tinfo.get(this);
                        if(i&&i.onstop){var f=i.onstop;i.onstop=null;f();}
                    }catch(e){}
                    return r;
                },'stop');
            }
        }catch(e){}
    }

    // ---- Identifiers, one set per site ------------------------------------
    // A real phone hands a different set to every site, keeps a site's own set
    // the same forever, and never lets two sites share one. The site's own name
    // goes into the mix, so a page that asks at the very first moment gets its
    // own values and never the previous site's.

    function siteKey(){
        try{
            var h=location.hostname;
            if(h)return h;
            var o=location.origin;
            if(o&&o!=='null')return o;
        }catch(e){}
        return 'local';
    }

    // Deterministic per site and handle: a standard v4-shaped identifier, the
    // shape the recording shows, with the version and variant nibbles set the
    // way a real UUID carries them.
    function expandId(handle,tag){
        var s=gs();
        var seed=(s.idsec||'')+'|'+siteKey()+'|'+(tag||'')+'|'+(handle||'');
        var h1=2166136261;
        for(var i=0;i<seed.length;i++){
            h1=h1^seed.charCodeAt(i);
            h1=Math.imul(h1,16777619);
        }
        var st=h1>>>0;
        var hex='';
        while(hex.length<32){
            st=(Math.imul(st,1664525)+1013904223)>>>0;
            hex+=(st>>>28).toString(16);
        }
        hex=hex.slice(0,32);
        hex=hex.slice(0,12)+'4'+hex.slice(13,16)+'8'+hex.slice(17,32);
        return hex.slice(0,8)+'-'+hex.slice(8,12)+'-'+hex.slice(12,16)+'-'+hex.slice(16,20)+'-'+hex.slice(20,32);
    }

    // Rewrites the handles the app handed in into this site's own identifiers.
    // Inert without a secret, which is what the untouched path leaves it as.
    _s._siteIds=function(){
        try{
            var s=gs();
            if(!s||!s.idsec)return;
            var i;
            if(s.auditList&&s.auditList.length){
                for(i=0;i<s.auditList.length;i++){
                    var c=s.auditList[i];
                    if(!c||!c.h)continue;
                    c.deviceId=expandId(c.h,'device');
                    c.groupId=expandId(c.h,'group');
                }
            }
            if(s.auditMics&&s.auditMics.length){
                for(i=0;i<s.auditMics.length;i++){
                    var m=s.auditMics[i];
                    if(!m||!m.h)continue;
                    m.deviceId=expandId(m.h,'device');
                    // Shares the GROUP of the camera it sits beside, and never
                    // an identity -- no real device shares one of those.
                    m.groupId=expandId(m.gh||m.h,'group');
                }
                s.auditMic=s.auditMics[0]||s.auditMic;
            }
        }catch(e){}
    };

    // The shape the readings recorded: a lowercase version-4 identifier.
    var _uuidRe=/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

    function makeUuid(){
        try{
            if(window.crypto&&crypto.randomUUID)return crypto.randomUUID();
        }catch(e){}
        var b=null;
        try{b=new Uint8Array(16);crypto.getRandomValues(b);}catch(e2){b=null;}
        if(!b){
            b=new Array(16);
            for(var i=0;i<16;i++)b[i]=Math.floor(Math.random()*256);
        }
        b[6]=(b[6]&15)|64;
        b[8]=(b[8]&63)|128;
        var out='';
        for(var j=0;j<16;j++){
            var h=b[j].toString(16);
            if(h.length<2)h='0'+h;
            out+=h;
            if(j===3||j===5||j===7||j===9)out+='-';
        }
        return out;
    }

    // Only steps in when the engine's own value is not already in that shape, so
    // a correct identifier is never replaced for the sake of it.
    function ensureUuidId(track){
        try{
            var cur=track.id;
            if(typeof cur==='string'&&_uuidRe.test(cur))return;
            trackInfo(track).id=makeUuid();
        }catch(e){}
    }

    // ---- Request prompt bridge -------------------------------------------
    // Resolves with null whenever anything is missing, so a page can never hang.
    var _prq=Object.create(null);
    var _prid=0;

    function askNative(kind,info){
        return new Promise(function(resolve){
            try{
                var s=gs();
                var mh=window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.fslPrompt;
                if(!mh){resolve(null);return;}
                var id=++_prid;
                var done=false;
                var finish=function(d){if(done)return;done=true;delete _prq[id];resolve(d);};
                _prq[id]=finish;
                setTimeout(function(){finish(null);},(((s&&s.prsec)||20)*1000)+2500);
                mh.postMessage({id:id,kind:kind,info:info||{},url:location.href});
            }catch(e){resolve(null);}
        });
    }

    _s._resolvePrompt=function(id,d){var f=_prq[id];if(f)f(d);};

    function reportStatus(facing,active,audio){
        try{
            var s=gs();
            if(!s||!s.rep)return;
            var mh=window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.fslStatus;
            if(!mh)return;
            var rq=s._req||{};
            var msg={facing:facing||'',active:!!active,audio:!!audio,fi:s.fi||0,bi:s.bi||0};
            if(active){
                msg.w=rq.w||0;
                msg.h=rq.h||0;
                msg.fps=rq.fps||0;
                msg.label=(rq.cam&&rq.cam.label)||'';
                msg.format='I420';
                // The frame really being drawn into, which is what the app's
                // live zoom and its framing have to act on. Taken off the
                // canvas rather than the request, because a request that named
                // no size is answered from the camera's own default.
                if(s._lv&&s._lv.cnv){
                    msg.cw=s._lv.cnv.width||0;
                    msg.ch=s._lv.cnv.height||0;
                }
            }
            mh.postMessage(msg);
        }catch(e){}
    }

    function reportServed(isBack,slot){
        try{
            var s=gs();
            if(!s||!s.rep)return;
            var mh=window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.fslStatus;
            if(!mh)return;
            mh.postMessage({served:true,facing:isBack?'environment':'user',slot:slot,fi:s.fi||0,bi:s.bi||0});
        }catch(e){}
    }

    function reportPass(isBack,done){
        try{
            var s=gs();
            if(!s||!s.rep)return;
            var mh=window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.fslStatus;
            if(!mh)return;
            mh.postMessage({pass:true,done:!!done,facing:isBack?'environment':'user',fi:s.fi||0,bi:s.bi||0});
        }catch(e){}
    }

    // Keeps the pill and the request card showing the item that really is next.
    function reportQueue(){
        try{
            var s=gs();
            if(!s||!s.rep)return;
            var mh=window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.fslStatus;
            if(!mh)return;
            mh.postMessage({queue:true,fi:s.fi||0,bi:s.bi||0});
        }catch(e){}
    }

    function reportEased(level,facing){
        try{
            var s=gs();
            if(!s||!s.rep)return;
            var mh=window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.fslStatus;
            if(!mh)return;
            mh.postMessage({eased:level,facing:facing||''});
        }catch(e){}
    }

    // ---- Capability checking ---------------------------------------------
    // Only a hard constraint can make a request impossible; ideal values always fit.
    function hardVal(c){
        if(c===null||c===undefined)return null;
        if(typeof c==='object'){
            if(typeof c.exact==='number')return c.exact;
            if(typeof c.min==='number')return c.min;
        }
        return null;
    }

    function reqNum(c){
        if(c===null||c===undefined)return null;
        if(typeof c==='number')return c;
        if(typeof c==='object'){
            if(typeof c.exact==='number')return c.exact;
            if(typeof c.ideal==='number')return c.ideal;
            if(typeof c.min==='number')return c.min;
            if(typeof c.max==='number')return c.max;
        }
        return null;
    }

    // ---- The measured mode ladder -----------------------------------------
    // What the readings actually show this platform doing: an explicit size is
    // honoured verbatim, a missing dimension is filled in at 4:3, an
    // aspect-only ask is answered from a 640-wide base by truncation -- which
    // is why an exact 16:9 comes back 640x359 and not 640x360 -- and an
    // over-large IDEAL is quietly substituted with the camera's own maximum
    // rather than refused. Only a HARD value over the ceiling is refused.

    var AR_BASE=640;
    var AR_FALLBACK=1.3333;

    // The camera a request lands on. A pinned id wins; otherwise a bare facing
    // request lands on the plain "Back Camera"/"Front Camera" entry, which is
    // the one the readings recorded for an unpinned ask.
    function auditCamFor(facing,devId){
        var s=gs();
        var list=s.auditList;
        if(!list||!list.length)return null;
        var i;
        if(devId){
            for(i=0;i<list.length;i++){if(list[i].deviceId===devId)return list[i];}
        }
        if(!facing)return null;
        var want=(facing==='environment')?'environment':'user';
        var plain=(want==='environment')?'Back Camera':'Front Camera';
        for(i=0;i<list.length;i++){if(list[i].label===plain)return list[i];}
        for(i=0;i<list.length;i++){if(list[i].facing===want)return list[i];}
        return null;
    }

    function knownDeviceId(did){
        var s=gs();
        var list=s.auditList;
        if(!list||!list.length)return true;
        for(var i=0;i<list.length;i++){if(list[i].deviceId===did)return true;}
        var fp=s.fp||{},bp=s.bp||{};
        if(fp.deviceId&&fp.deviceId===did)return true;
        if(bp.deviceId&&bp.deviceId===did)return true;
        return false;
    }

    // Only an exact facing can contradict a pinned id. An ideal one is a wish.
    function exactFacing(vidC){
        if(!vidC||typeof vidC!=='object')return null;
        var fm=vidC.facingMode;
        if(!fm||typeof fm!=='object')return null;
        var e=fm.exact;
        if(typeof e==='string')return e;
        if(Array.isArray(e)&&typeof e[0]==='string')return e[0];
        return null;
    }

    function resolveMode(cam,vidC){
        var natW=(cam&&cam.nat)?cam.nat[0]:0;
        var natH=(cam&&cam.nat)?cam.nat[1]:0;
        var defW=(cam&&cam.def)?cam.def[0]:0;
        var defH=(cam&&cam.def)?cam.def[1]:0;
        var rates=(cam&&cam.rates&&cam.rates.length)?cam.rates:[15,30,60];
        var outFps=(cam&&cam.fps)?cam.fps:30;

        var w=reqNum(vidC&&vidC.width);
        var h=reqNum(vidC&&vidC.height);
        var ar=reqNum(vidC&&vidC.aspectRatio);
        var fr=reqNum(vidC&&vidC.frameRate);

        var outW,outH,sub=false;
        if(w>0&&h>0){outW=Math.round(w);outH=Math.round(h);}
        else if(w>0){outW=Math.round(w);outH=Math.floor(outW/AR_FALLBACK);}
        else if(h>0){outH=Math.round(h);outW=Math.floor(outH*AR_FALLBACK);}
        else if(ar>0){outW=AR_BASE;outH=Math.floor(AR_BASE/ar);}
        else{outW=defW;outH=defH;}

        // Over the ceiling on an ideal: hand back this camera's own maximum,
        // ignoring the asked-for shape, exactly as every camera did.
        if(natW>0&&natH>0&&(outW>natW||outH>natH)){outW=natW;outH=natH;sub=true;}
        if(!(outW>0))outW=natW||1280;
        if(!(outH>0))outH=natH||720;

        if(fr>0){
            var bd=-1;
            for(var i=0;i<rates.length;i++){
                var d=Math.abs(rates[i]-fr);
                if(bd<0||d<bd){bd=d;outFps=rates[i];}
            }
        }
        return {w:outW,h:outH,fps:outFps,sub:sub};
    }

    // ---- Refusals, in the order and wording the readings recorded ---------

    // The browser's own type layer throws these out before a camera is asked.
    function nonFinite(c){
        if(c===null||c===undefined)return false;
        if(typeof c==='number')return !isFinite(c);
        if(typeof c==='object'){
            var k=['exact','ideal','min','max'];
            for(var i=0;i<k.length;i++){
                var v=c[k[i]];
                if(typeof v==='number'&&!isFinite(v))return true;
            }
        }
        return false;
    }

    function invertedRange(c){
        if(!c||typeof c!=='object')return false;
        return typeof c.min==='number'&&typeof c.max==='number'&&c.min>c.max;
    }

    // Text where a number belongs, or a negative one. A fraction is fine --
    // the readings show 640.5 granted.
    function malformed(c){
        if(c===null||c===undefined)return false;
        if(typeof c==='string')return true;
        if(typeof c==='number')return c<0;
        if(typeof c==='object'){
            var k=['exact','ideal','min','max'];
            for(var i=0;i<k.length;i++){
                var v=c[k[i]];
                if(typeof v==='string')return true;
                if(typeof v==='number'&&v<0)return true;
            }
        }
        return false;
    }

    function capabilityReject(vidC){
        var s=gs();
        if(!s.cap||!vidC||typeof vidC!=='object')return null;
        var lim=s.caplim;
        if(!lim)return null;

        if(nonFinite(vidC.frameRate)||nonFinite(vidC.width)
            ||nonFinite(vidC.height)||nonFinite(vidC.aspectRatio))return 'nonfinite';

        if(invertedRange(vidC.width)||invertedRange(vidC.height)
            ||malformed(vidC.width)||malformed(vidC.height))return 'width';
        if(invertedRange(vidC.frameRate)||malformed(vidC.frameRate))return 'frameRate';

        var did=extractDeviceId(vidC);
        if(did&&!knownDeviceId(did))return 'deviceId';

        var cam=did?auditCamFor(null,did):null;
        var wantFacing=exactFacing(vidC);
        if(cam&&wantFacing&&cam.facing!==wantFacing)return 'facingMode';
        if(!cam)cam=auditCamFor(wantFacing||extractFacing(vidC),null);

        var maxW=(cam&&cam.nat)?cam.nat[0]:lim.maxWidth;
        var maxH=(cam&&cam.nat)?cam.nat[1]:lim.maxHeight;
        var maxFps=lim.maxFrameRate;
        if(cam&&cam.rates&&cam.rates.length)maxFps=cam.rates[cam.rates.length-1];

        var fr=hardVal(vidC.frameRate);
        // A hard zero is not video at all, and was refused naming frameRate.
        if(fr!==null&&(fr>maxFps||fr===0))return 'frameRate';
        var w=hardVal(vidC.width);
        if(w!==null&&w>maxW)return 'width';
        var h=hardVal(vidC.height);
        // An impossible size was only ever blamed on width, never on height.
        if(h!==null&&h>maxH)return 'width';
        return null;
    }

    function makeOverconstrained(which){
        var s=gs();
        var lim=s.caplim||{};
        // A non-finite number never reaches a camera: the type layer rejects it
        // with a TypeError, and that is a different answer to a refusal.
        if(which==='nonfinite'){
            var tmsg=lim.typeMsg||'The provided value is non-finite';
            var te=new TypeError(tmsg);
            try{
                var tmh=window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.fslStatus;
                if(tmh)tmh.postMessage({refused:'',name:lim.typeName||'TypeError',message:tmsg,url:location.href});
            }catch(t2){}
            return te;
        }
        var msg=lim.msg||'Invalid constraint';
        var nm=lim.name||'OverconstrainedError';
        var e=null;
        try{e=new OverconstrainedError(which,msg);}catch(x){e=null;}
        if(!e){
            try{e=new DOMException(msg,nm);}catch(y){e=new Error(msg);e.name=nm;}
            try{Object.defineProperty(e,'constraint',{value:which,configurable:true,enumerable:true});}catch(z){}
        }
        try{
            var mh=window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.fslStatus;
            if(mh)mh.postMessage({refused:which,name:nm,message:msg,url:location.href});
        }catch(w2){}
        return e;
    }

    // ---- Live-feed motion (never used by the file path) --------------------
    // Everything expensive is baked once per feed. Per frame the loop does one
    // wipe plus one blit of an already-sized bitmap, so a moving feed costs
    // about what the still feed it replaces costs.

    // Furthest the picture can leave centre, as a fraction of the frame.
    function motionTravel(k){return 0.0160*k;}

    // Exactly enough zoom to keep the frame covered: travel on both sides, the
    // shrink half of the breath, and a small allowance for tilt. Nothing more,
    // so a gentle setting crops almost nothing and a strong one cannot run dry.
    function motionCoverZoom(k){return 1+(2*0.0160+0.008+0.004)*k;}

    // Identifies what the baked bitmap was built for. Switches apply without a
    // reload, so a change to strength or either look has to rebuild it -- a
    // stronger setting travels further than the old margin allowed.
    function motionSig(s,crop){
        var base=(s.mok||1)+'|'+(s.grain?1:0)+'|'+(s.skin?1:0);
        if(!crop)return base;
        return base+'|'+crop.z+'|'+crop.px+'|'+crop.py;
    }

    // Which of the four frame shapes this canvas is. FrameShape.swift uses the
    // same boundaries, so the app and the page always pick the same framing --
    // a change to these numbers must land there as well.
    function frameShapeKey(cw,ch){
        if(!(cw>0)||!(ch>0))return 'w';
        var a=cw/ch;
        if(a>=1.55)return 'w';
        if(a>=1.15)return 'f';
        if(a>0.87)return 's';
        return 'p';
    }

    function stillCropFor(isBack,slot,cw,ch){
        var s=gs();
        if(!s||!s.crop)return null;
        var map=isBack?(slot===1?s.bc2:s.bc):(slot===1?s.fc2:s.fc);
        if(!map)return null;
        var arr=map[frameShapeKey(cw,ch)];
        if(!arr||arr.length<3)return null;
        var z=+arr[0],px=+arr[1],py=+arr[2];
        if(!(z>0))return null;
        if(z===1&&px===0.5&&py===0.5)return null;
        return {z:z,px:px,py:py};
    }

    // A running clip's live zoom. 1 is the cover-fit every video has always
    // been drawn at, so an untouched feed draws exactly as it did before.
    function videoZoomFor(isBack){
        var s=gs();
        if(!s)return 1;
        var z=+(isBack?s.lzb:s.lzf);
        return (z>0)?z:1;
    }

    // Real frame delivery clusters tightly around the camera's own rate, with the
    // occasional late one. A flat spread across a wide band is the one shape
    // hardware never produces, so the gap is drawn from a peak instead and a rare
    // outlier is added on top.
    function frameGap(interval){
        var s=gs();
        if(!s.jit)return interval;
        // Three uniforms average to very nearly a bell, and cost three multiplies
        // rather than a logarithm.
        var u=(Math.random()+Math.random()+Math.random())*0.33333333;
        var f=1+(u-0.5)*2*0.045;
        // About one frame in ninety arrives noticeably late, which is what a real
        // pipeline does whenever it has to wait for anything.
        if(Math.random()<0.011)f+=0.10+Math.random()*0.22;
        return interval*f;
    }

    // Brightness and warmth as a camera's own metering really behaves: always
    // drifting, never settling on one number. Returns null when the switch is
    // off, which leaves the wipe exactly the clear it has always been.
    function exposureAt(t,rig){
        var s=gs();
        if(!s.expo)return null;
        // Eased down with everything else when frames start costing too much, so
        // this can never be the thing that ruins a feed.
        var g=(rig&&rig.ease!==undefined)?rig.ease:1;
        if(!(g>0))return null;
        // Two slow waves at unrelated speeds, so it never reads as a loop.
        var b=Math.sin(t*0.000181)*0.6+Math.sin(t*0.000437+2.1)*0.4;
        var w=Math.sin(t*0.000149+1.3)*0.6+Math.sin(t*0.000353+0.7)*0.4;
        var hunt=0;
        if(rig&&rig.reAt>=0){
            // A hand-over points the feed at something new, so it meters again:
            // one overshoot, a settle, then back to the slow drift.
            var p=(t-rig.reAt)/900;
            if(p<0)p=0;
            if(p<1){hunt=Math.sin(p*Math.PI*1.5)*(1-p)*(1-p);}
            else{rig.reAt=-1;}
        }
        var lift=(b*0.018+hunt*0.05)*g;
        var warm=w*0.013*g;
        var r,gg,bb;
        if(lift>=0){r=255;gg=249;bb=240;}
        else{r=9;gg=11;bb=17;}
        r=r+warm*90;bb=bb-warm*90;
        if(r<0)r=0;else if(r>255)r=255;
        if(bb<0)bb=0;else if(bb>255)bb=255;
        return {lift:lift,css:'rgb('+(r|0)+','+(gg|0)+','+(bb|0)+')'};
    }

    function makeNoiseTile(size){
        var c=document.createElement('canvas');
        c.width=size;c.height=size;
        var x=c.getContext('2d');
        var id=x.createImageData(size,size);
        var d=id.data;
        for(var i=0;i<d.length;i+=4){
            var v=128+(Math.random()*2-1)*34;
            d[i]=v;d[i+1]=v;d[i+2]=v;d[i+3]=255;
        }
        x.putImageData(id,0,0);
        return c;
    }

    // Bakes the source, and any one-off look, into a bitmap at draw size. Doing
    // this once means each frame is a near 1:1 blit instead of rescaling a full
    // resolution photo, and the warmth and grain cost nothing per frame.
    function makeMotionRig(img,cw,ch,crop){
        var s=gs();
        var k=s.mok||1;
        var zoom=motionCoverZoom(k);
        var bw=Math.max(2,Math.round(cw*zoom));
        var bh=Math.max(2,Math.round(ch*zoom));
        var rig={
            t0:nowMs(),jx:0,jy:0,jAt:-99999,jNext:2400+Math.random()*3600,
            bmp:null,bw:bw,bh:bh,ease:1,cost:0,slow:0,eased:0,frozenDrawn:false,
            // A real camera meters the moment it opens, so the settle runs once
            // at the start too, not only after a hand-over.
            reAt:0,
            sig:motionSig(s,crop)
        };
        try{
            var b=document.createElement('canvas');
            b.width=bw;b.height=bh;
            var bx=b.getContext('2d');
            var iw=img.naturalWidth||img.width||bw;
            var ih=img.naturalHeight||img.height||bh;
            var sc=Math.max(bw/iw,bh/ih);
            var dw=iw*sc,dh=ih*sc;
            var x=(bw-dw)*0.5,y=(bh-dh)*0.5;
            if(crop){
                dw*=crop.z;dh*=crop.z;
                x=(bw-dw)*crop.px;y=(bh-dh)*crop.py;
            }
            bx.drawImage(img,x,y,dw,dh);
            if(s.skin){
                try{
                    var g=bx.createRadialGradient(bw*0.5,bh*0.42,Math.min(bw,bh)*0.08,bw*0.5,bh*0.52,Math.max(bw,bh)*0.78);
                    g.addColorStop(0,'rgba(255,228,201,0.15)');
                    g.addColorStop(0.55,'rgba(255,214,188,0.05)');
                    g.addColorStop(1,'rgba(20,15,24,0.20)');
                    bx.save();
                    bx.globalCompositeOperation='soft-light';
                    bx.fillStyle=g;
                    bx.fillRect(0,0,bw,bh);
                    bx.restore();
                }catch(e){}
            }
            if(s.grain){
                try{
                    var pat=bx.createPattern(makeNoiseTile(96),'repeat');
                    if(pat){
                        bx.save();
                        bx.globalCompositeOperation='overlay';
                        bx.globalAlpha=0.05+0.035*k;
                        bx.fillStyle=pat;
                        bx.fillRect(0,0,bw,bh);
                        bx.restore();
                    }
                }catch(e){}
            }
            rig.bmp=b;
        }catch(e){rig.bmp=null;}
        return rig;
    }

    // One wipe, one blit. Returns the running cost so the governor can react.
    //
    // `o` carries a handover fade's opacity, travel (dx/dy) and the zoom that
    // keeps that travel covered, plus the still's crop offset (cx/cy). The crop
    // is already baked into the rig bitmap, so cx/cy only move the picture on
    // the no-bitmap fallback -- applying it to the bitmap too would pan twice
    // and open a black band at the frame edge.
    //
    // The app's Frame Check preview (FrameRigMath.swift) mirrors this function
    // constant for constant; a change here must land there as well.
    function drawMotionFrame(rig,ctx,img,cw,ch,dw,dh,o){
        var s=gs();
        var al=(o&&o.alpha!==undefined)?o.alpha:1;
        var ox=o?(o.dx||0):0;
        var oy=o?(o.dy||0):0;
        var cx=o?(o.cx||0):0;
        var cy=o?(o.cy||0):0;
        var oz=o?(o.zoom||1):1;
        if(!rig||!rig.bmp){
            if(o&&o.clear)ctx.clearRect(0,0,cw,ch);
            var pw=dw*oz,ph=dh*oz;
            if(al!==1){ctx.save();ctx.globalAlpha=al;}
            ctx.drawImage(img,(cw-pw)*0.5+ox+cx,(ch-ph)*0.5+oy+cy,pw,ph);
            if(al!==1)ctx.restore();
            return 0;
        }
        var k=(s.mok||1)*rig.ease;
        var began=nowMs();
        var t=began-rig.t0;

        var dx=0,dy=0,breathe=1,tilt=0,je=0;
        if(!s.frz&&k>0){
            dx=(Math.sin(t*0.00037)*0.6+Math.sin(t*0.00091+1.7)*0.3+Math.sin(t*0.0021+0.4)*0.1)*cw*0.010*k;
            dy=(Math.cos(t*0.00043+0.9)*0.6+Math.cos(t*0.00107+2.3)*0.3+Math.sin(t*0.0019+1.1)*0.1)*ch*0.010*k;
            breathe=1+0.008*k*Math.sin(t*0.00052+0.6);
            tilt=0.0016*k*Math.sin(t*0.00061+2.1);
            if(t>rig.jNext){
                rig.jx=(Math.random()*2-1)*cw*0.0060*k;
                rig.jy=(Math.random()*2-1)*ch*0.0060*k;
                rig.jAt=t;
                rig.jNext=t+2200+Math.random()*4200;
            }
            var jp=Math.max(0,1-(t-rig.jAt)/540);
            je=jp*jp*(3-2*jp);
        }

        // Wipe first so a border can never keep the previous frame, then move
        // the picture with one even scale. No squeeze, ever.
        //
        // The wipe doubles as the exposure drift: filling it with the drift
        // colour instead of clearing it is the same single operation, and the
        // blit below carries the amount as its own opacity. So brightness and
        // warmth breathe for nothing -- no per-frame filter, no second pass.
        var lift=0;
        if(!o||o.clear){
            var ex=exposureAt(t,rig);
            if(ex){
                lift=ex.lift;
                ctx.fillStyle=ex.css;
                ctx.fillRect(0,0,cw,ch);
            }else{
                ctx.clearRect(0,0,cw,ch);
            }
        }
        ctx.save();
        var alEff=lift?al*(1-(lift<0?-lift:lift)):al;
        if(alEff!==1)ctx.globalAlpha=alEff;
        ctx.translate(cw*0.5+dx+rig.jx*je+ox,ch*0.5+dy+rig.jy*je+oy);
        if(tilt)ctx.rotate(tilt);
        var evenScale=breathe*oz;
        if(evenScale!==1)ctx.scale(evenScale,evenScale);
        ctx.drawImage(rig.bmp,-rig.bw*0.5,-rig.bh*0.5,rig.bw,rig.bh);
        ctx.restore();

        var spent=nowMs()-began;
        rig.cost=rig.cost?(rig.cost*0.85+spent*0.15):spent;
        return rig.cost;
    }

    // Motion must never be the thing that ruins a live feed. If frames start
    // costing too much, strength eases down, then off, and the app is told.
    function governMotion(rig,cost,interval,facing){
        if(!rig||!cost||!(interval>0))return;
        if(cost>interval*0.55){
            rig.slow++;
            if(rig.slow>=12&&rig.ease>0){
                rig.slow=0;
                rig.ease=(rig.ease>0.5)?0.5:0;
                rig.eased=(rig.ease>0)?1:2;
                reportEased(rig.eased,facing);
            }
        }else if(rig.slow>0){rig.slow--;}
    }

    function initCanvas(facing){
        var s=gs();
        var isBack=(facing==='environment');
        var p=isBack?(s.bp||s.fp||{}):(s.fp||{});
        var w=(p&&p.width)?p.width:1280;
        var h=(p&&p.height)?p.height:720;
        // The picture is made at exactly the size the track will report.
        var rq=s._req;
        if(rq&&rq.facing===(isBack?'environment':'user')&&rq.w>0&&rq.h>0){
            w=rq.w;h=rq.h;
        }
        var ck=isBack?'_cb':'_cf';
        var xk=isBack?'_xb':'_xf';
        if(!s[ck]){
            s[ck]=document.createElement('canvas');
            s[ck].width=w;
            s[ck].height=h;
            s[xk]=s[ck].getContext('2d');
            s[xk].fillStyle='#000';
            s[xk].fillRect(0,0,w,h);
        } else if(s[ck].width!==w||s[ck].height!==h){
            s[ck].width=w;
            s[ck].height=h;
            s[xk].fillStyle='#000';
            s[xk].fillRect(0,0,w,h);
        }
        s._c=s[ck];
        s._x=s[xk];
    }

    function cleanup(){
        var s=gs();
        if(s._ri){cancelAnimationFrame(s._ri);s._ri=null;}
        // Any handover in flight belongs to the feed being torn down.
        if(s._fx){disposeLayer(s._fx.out);disposeLayer(s._fx.inc);s._fx=null;}
        s._fxc=null;
        if(s._lv){disposeLayer(s._lv.lay);s._lv=null;}
        if(s._ve){try{s._ve.pause();s._ve.removeAttribute('src');s._ve.load();}catch(e){}s._ve=null;}
        if(s._st){try{s._st.getTracks().forEach(function(t){t.stop();});}catch(e){}s._st=null;}
    }

    function safariVideoLabel(isEnv){return isEnv?'Back Camera':'Front Camera';}
    function safariMicLabel(){return 'iPhone Microphone';}

    function forceTrackLabel(track,label){
        try{
            Object.defineProperty(track,'label',{configurable:true,enumerable:true,get:function(){return label;}});
        }catch(e){
            try{track.label=label;}catch(e2){}
        }
    }

    function advanceSeq(isBack){
        var s=gs();
        var seq=isBack?(s.bseq||[]):(s.fseq||[]);
        if(!seq||seq.length<=1){
            if(s.onepass)reportPass(isBack,true);
            return;
        }
        if(s.onepass){
            var idx=isBack?(s.bi||0):(s.fi||0);
            if(idx+1>=seq.length){
                reportPass(isBack,true);
                return;
            }
            if(isBack)s.bi=idx+1; else s.fi=idx+1;
            reportQueue();
            reportPass(isBack,false);
            return;
        }
        if(isBack){s.bi=((s.bi||0)+1)%seq.length;}
        else{s.fi=((s.fi||0)+1)%seq.length;}
        // The page owns the position, so tell the app which item is next now.
        reportQueue();
    }

    function currentSeqItem(isBack){
        var s=gs();
        var seq=isBack?(s.bseq||[]):(s.fseq||[]);
        if(seq&&seq.length){
            var idx=isBack?(s.bi||0):(s.fi||0);
            if(idx<0||idx>=seq.length)idx=0;
            return seq[idx];
        }
        return null;
    }

    function hasAnyMedia(s){
        if(!s)return false;
        if(s.is||s.vs||s.fis||s.fvs||s.bis||s.bvs)return true;
        if(s.fseq&&s.fseq.length)return true;
        if(s.bseq&&s.bseq.length)return true;
        return false;
    }

    // Reports the feed ending so the live indicator cannot stay lit after a site
    // is done with the camera. Inert unless status reporting is switched on.
    function watchTrackEnd(track){
        try{
            var s=gs();
            if(!s||!s.rep||!track)return;
            if(!firstTouch(track))return;
            var done=false;
            var fire=function(){
                if(done)return;
                done=true;
                reportStatus('',false);
            };
            try{track.addEventListener('ended',fire);}catch(e){}
            if(s.auditList&&s.auditList.length){
                // Watched from the shared prototype, so the feed keeps no own
                // method for a page to notice.
                ensureTrackProto();
                trackInfo(track).onstop=fire;
                return;
            }
            var origStop=track.stop;
            if(typeof origStop==='function'){
                track.stop=function(){
                    var r=origStop.apply(this,arguments);
                    fire();
                    return r;
                };
            }
        }catch(e){}
    }

    function patchTrack(stream,requestedFacing){
        try{
            var tracks=stream.getVideoTracks();
            if(tracks.length>0){
                var track=tracks[0];
                var s=gs();
                watchTrackEnd(track);
                var isEnv=(requestedFacing==='environment');
                var p=isEnv?(s.bp||s.fp||{}):(s.fp||{});
                var devId=p.deviceId||(isEnv?'com.apple.avfoundation.avcapturedevice.back':'com.apple.avfoundation.avcapturedevice.front');
                var grpId=p.groupId||devId;
                var w=p.width||1280;
                var h=p.height||720;
                var fps=p.frameRate||30;
                var fm=requestedFacing||p.facingMode||'user';
                var ar=p.aspectRatio||(w/h);
                var rm=p.resizeMode||'none';
                // With the ladder on, the track reports the size the request
                // really resolved to, and the picture is made at that same size,
                // so getSettings and videoWidth can never disagree.
                var cam=null;
                var rq=s._req;
                if(rq&&rq.facing===(isEnv?'environment':'user')){
                    if(rq.w>0)w=rq.w;
                    if(rq.h>0)h=rq.h;
                    if(rq.fps>0)fps=rq.fps;
                    ar=w/h;
                    cam=rq.cam||null;
                }
                if(cam){
                    devId=cam.deviceId;
                    grpId=cam.groupId;
                    fm=cam.facing||fm;
                }
                var lbl=cam?cam.label:safariVideoLabel(isEnv);

                // Built once and shared by both placements below, so the two can
                // never answer differently.
                var carryOver=function(out,base){
                    try{
                        var ks=Object.keys(base||{});
                        for(var i=0;i<ks.length;i++){
                            if(!(ks[i] in out))out[ks[i]]=base[ks[i]];
                        }
                    }catch(e){}
                    return out;
                };
                // Rebuilt in the order the engine itself fills these in.
                // Appending ours to whatever the canvas feed happened to carry
                // would put them in an order no real feed uses, and key order is
                // readable on its own.
                var buildSettings=function(base){
                    var out={};
                    out.width=w;
                    out.height=h;
                    out.aspectRatio=ar;
                    out.frameRate=fps;
                    out.facingMode=fm;
                    out.resizeMode=rm;
                    out.deviceId=devId;
                    out.groupId=grpId;
                    return carryOver(out,base);
                };
                var buildCaps=function(base){
                    var out={};
                    out.width={min:p.minWidth||1,max:p.maxWidth||w};
                    out.height={min:p.minHeight||1,max:p.maxHeight||h};
                    out.aspectRatio={min:0.000277,max:ar>1?ar+1:1920};
                    out.frameRate={min:p.minFrameRate||1,max:p.maxFrameRate||fps};
                    out.facingMode=p.capFacingModes||[fm];
                    out.resizeMode=p.capResizeModes||['none','crop-and-scale'];
                    // This camera's own ceiling and controls, not a shared one:
                    // only the multi-lens back camera goes below 1x, only it has
                    // a torch, and two of the five publish no white balance.
                    if(cam){
                        out.width={min:1,max:cam.nat[0]};
                        out.height={min:1,max:cam.nat[1]};
                        if(cam.rates&&cam.rates.length){
                            out.frameRate={min:1,max:cam.rates[cam.rates.length-1]};
                        }
                        out.facingMode=[cam.facing];
                    }
                    out.deviceId=devId;
                    out.groupId=grpId;
                    if(cam){
                        out.zoom={min:cam.minZoom,max:cam.maxZoom};
                        if(cam.wb&&cam.wb.length)out.whiteBalanceMode=cam.wb.slice();
                        if(cam.torch)out.torch=[false,true];
                    }
                    return carryOver(out,base);
                };

                if(s.auditList&&s.auditList.length){
                    // A real feed carries none of this on the feed itself.
                    ensureTrackProto();
                    var ti=trackInfo(track);
                    ti.label=lbl;
                    ti.settings=buildSettings;
                    ti.caps=buildCaps;
                    ensureUuidId(track);
                }else{
                    forceTrackLabel(track,lbl);
                    var origGS=track.getSettings;
                    track.getSettings=maskNative(function getSettings(){
                        return buildSettings(origGS?origGS.call(this):{});
                    },'getSettings');
                    if(track.getCapabilities){
                        var origGC=track.getCapabilities;
                        track.getCapabilities=maskNative(function getCapabilities(){
                            return buildCaps(origGC?origGC.call(this):{});
                        },'getCapabilities');
                    }
                }
            }
        }catch(e){}
        return stream;
    }

    function patchAudioTrack(stream){
        try{
            var s=gs();
            var mp=s.mp||{};
            // The audited input: its own identity, and only the GROUP shared with
            // the camera it sits beside. Sharing an identity is what no real
            // device does.
            var am=s.auditMic||null;
            var tracks=stream.getAudioTracks();
            if(tracks.length>0){
                var track=tracks[0];
                if(am){
                    ensureTrackProto();
                    var ati=trackInfo(track);
                    ati.label=am.label||safariMicLabel();
                    ati.settings=function(base){
                        var out={};
                        out.sampleRate=am.sampleRate||48000;
                        out.sampleSize=am.sampleSize||16;
                        out.channelCount=am.channelCount||1;
                        out.deviceId=am.deviceId;
                        out.groupId=am.groupId;
                        out.echoCancellation=!!am.echoCancellation;
                        out.autoGainControl=!!am.autoGainControl;
                        out.noiseSuppression=!!am.noiseSuppression;
                        out.latency=(typeof am.latency==='number')?am.latency:0;
                        try{
                            var ks=Object.keys(base||{});
                            for(var i=0;i<ks.length;i++){
                                if(!(ks[i] in out))out[ks[i]]=base[ks[i]];
                            }
                        }catch(e){}
                        return out;
                    };
                    // The same facts as ranges, so getCapabilities and
                    // getSettings never disagree with each other.
                    ati.caps=function(base){
                        var out={};
                        var lat=(typeof am.latency==='number')?am.latency:0;
                        var sr=am.sampleRate||48000;
                        var ss=am.sampleSize||16;
                        var cc=am.channelCount||1;
                        out.sampleRate={min:sr,max:sr};
                        out.sampleSize={min:ss,max:ss};
                        out.channelCount={min:cc,max:cc};
                        out.latency={min:lat,max:lat};
                        out.echoCancellation=[!!am.echoCancellation];
                        out.autoGainControl=[!!am.autoGainControl];
                        out.noiseSuppression=[!!am.noiseSuppression];
                        out.deviceId=am.deviceId;
                        out.groupId=am.groupId;
                        try{
                            var ks=Object.keys(base||{});
                            for(var i=0;i<ks.length;i++){
                                if(!(ks[i] in out))out[ks[i]]=base[ks[i]];
                            }
                        }catch(e){}
                        return out;
                    };
                    ensureUuidId(track);
                    return stream;
                }
                forceTrackLabel(track,safariMicLabel());
                var origGS=track.getSettings;
                track.getSettings=function(){
                    var base=origGS?origGS.call(this):{};
                    base.deviceId=mp.deviceId||base.deviceId||'default';
                    base.groupId=mp.groupId||base.groupId||'';
                    base.sampleRate=mp.sampleRate||base.sampleRate||44100;
                    base.channelCount=mp.channelCount||base.channelCount||1;
                    return base;
                };
            }
        }catch(e){}
        return stream;
    }

    function imageStream(requestedFacing,imgSrc){
        return new Promise(function(resolve,reject){
            var s=gs();
            initCanvas(requestedFacing);
            var cnv=s._c,ctx=s._x;
            var img=new Image();
            img.crossOrigin='anonymous';
            img.onload=function(){
                var cw=cnv.width,ch=cnv.height;
                var iw=img.naturalWidth,ih=img.naturalHeight;
                var isBack=(requestedFacing==='environment');
                var item=currentSeqItem(isBack);
                var slot=(item&&typeof item.i==='number')?item.i:0;
                var crop=stillCropFor(isBack,slot,cw,ch);
                var scale=Math.max(cw/iw,ch/ih);
                var dw=iw*scale,dh=ih*scale;
                var ox=0,oy=0;
                if(crop){
                    dw*=crop.z;dh*=crop.z;
                    ox=(cw-dw)*crop.px-(cw-dw)*0.5;
                    oy=(ch-dh)*crop.py-(ch-dh)*0.5;
                }
                var p=isBack?(s.bp||s.fp||{}):(s.fp||{});
                var fps=p.frameRate||30;

                // Motion is a wrapper around the existing feed. With s.mo off the
                // capture call and the draw loop are exactly the original ones.
                // The layer object is the same one a later handover fades out, so
                // the movement it is part-way through carries over untouched.
                var lay={k:'i',img:img,rig:null,dw:dw,dh:dh,src:imgSrc,ox:ox,oy:oy,slot:slot,crop:crop||null};
                lay.rig=s.mo?makeMotionRig(img,cw,ch,crop):null;
                var opt=crop?{cx:ox,cy:oy,clear:true}:null;

                // Always paint before capturing so the handed-over feed already
                // carries a real frame; a site that measures it at once sees it.
                if(lay.rig){drawMotionFrame(lay.rig,ctx,img,cw,ch,dw,dh,opt);}
                else{
                    // Below cover-fit the picture no longer covers the frame, so
                    // the last frame's pixels must not survive around it.
                    if(crop&&crop.z<1)ctx.clearRect(0,0,cw,ch);
                    ctx.drawImage(img,(cw-dw)/2+ox,(ch-dh)/2+oy,dw,dh);
                }

                // The feed owns frame delivery, so a throttled screen clock can
                // slow the movement but can never stall the stream itself.
                var st=cnv.captureStream(fps);
                s._st=st;

                var interval=1000/(fps||30);
                var nextAt=nowMs()+interval;
                s._lv={facing:requestedFacing,cnv:cnv,ctx:ctx,fps:fps,interval:interval,lay:lay,nextAt:nextAt};
                var loop=function(){
                    if(!s.a){reportStatus('',false);return;}
                    var cropNow=stillCropFor(isBack,slot,cw,ch);
                    var scNow=Math.max(cw/iw,ch/ih);
                    var dwNow=iw*scNow,dhNow=ih*scNow;
                    var oxNow=0,oyNow=0;
                    if(cropNow){
                        dwNow*=cropNow.z;dhNow*=cropNow.z;
                        oxNow=(cw-dwNow)*cropNow.px-(cw-dwNow)*0.5;
                        oyNow=(ch-dhNow)*cropNow.py-(ch-dhNow)*0.5;
                    }
                    lay.dw=dwNow;lay.dh=dhNow;lay.ox=oxNow;lay.oy=oyNow;lay.crop=cropNow||null;
                    var optNow=cropNow?{cx:oxNow,cy:oyNow,clear:true}:null;
                    if(s.mo){
                        var rig=lay.rig;
                        if(!rig||rig.sig!==motionSig(s,cropNow)){rig=makeMotionRig(img,cw,ch,cropNow);lay.rig=rig;}
                        if(s.frz){
                            if(!rig.frozenDrawn){
                                drawMotionFrame(rig,ctx,img,cw,ch,dwNow,dhNow,optNow);
                                rig.frozenDrawn=true;
                            }
                        }else{
                            rig.frozenDrawn=false;
                            var n=nowMs();
                            if(n>=nextAt){
                                var cost=drawMotionFrame(rig,ctx,img,cw,ch,dwNow,dhNow,optNow);
                                governMotion(rig,cost,interval,requestedFacing);
                                nextAt=n+frameGap(interval);
                                if(s._lv)s._lv.nextAt=nextAt;
                            }
                        }
                    }else{
                        lay.rig=null;
                        if(cropNow&&cropNow.z<1)ctx.clearRect(0,0,cw,ch);
                        ctx.drawImage(img,(cw-dwNow)/2+oxNow,(ch-dhNow)/2+oyNow,dwNow,dhNow);
                    }
                    s._ri=requestAnimationFrame(loop);
                };
                s._ri=requestAnimationFrame(loop);
                resolve(patchTrack(st,requestedFacing));
            };
            img.onerror=function(){reject(new DOMException('Could not start video source','NotReadableError'));};
            img.src=imgSrc;
        });
    }

    function videoStream(requestedFacing,vidUrl){
        return new Promise(function(resolve,reject){
            var s=gs();
            initCanvas(requestedFacing);
            var cnv=s._c,ctx=s._x;
            var isBack=(requestedFacing==='environment');
            var loadVideo=function(src){
                var vid=document.createElement('video');
                vid.setAttribute('playsinline','');
                var advanceOnEnd=(s.adv==='videoend');
                vid.loop=!advanceOnEnd;
                vid.muted=true;
                vid.playsInline=true;
                vid.crossOrigin='anonymous';
                vid.src=src;
                s._ve=vid;
                if(advanceOnEnd){
                    vid.addEventListener('ended',function(){
                        advanceSeq(isBack);
                    });
                }
                vid.onloadeddata=function(){
                    vid.play().then(function(){
                        var cw=cnv.width,ch=cnv.height;
                        var vw=vid.videoWidth||cw,vh=vid.videoHeight||ch;
                        var z0=videoZoomFor(isBack);
                        var scale=Math.max(cw/vw,ch/vh);
                        var dw=vw*scale*z0,dh=vh*scale*z0;
                        if(z0<1)ctx.clearRect(0,0,cw,ch);
                        ctx.drawImage(vid,(cw-dw)/2,(ch-dh)/2,dw,dh);
                        var p=isBack?(s.bp||s.fp||{}):(s.fp||{});
                        var fps=p.frameRate||30;
                        var st=cnv.captureStream(fps);
                        s._st=st;
                        var lay={k:'v',vid:vid,src:vidUrl,blob:(src!==vidUrl)?src:null,lz:z0};
                        s._lv={
                            facing:requestedFacing,cnv:cnv,ctx:ctx,fps:fps,
                            interval:1000/(fps||30),nextAt:0,
                            lay:lay
                        };
                        var loop=function(){
                            if(!s.a||vid.paused||vid.ended)return;
                            var cw2=cnv.width,ch2=cnv.height;
                            var vw2=vid.videoWidth||cw2,vh2=vid.videoHeight||ch2;
                            // Read live so a zoom press lands on the very next
                            // frame without rebuilding anything.
                            var z2=videoZoomFor(isBack);
                            lay.lz=z2;
                            var sc2=Math.max(cw2/vw2,ch2/vh2)*z2;
                            var dw2=vw2*sc2,dh2=vh2*sc2;
                            if(z2<1)ctx.clearRect(0,0,cw2,ch2);
                            ctx.drawImage(vid,(cw2-dw2)/2,(ch2-dh2)/2,dw2,dh2);
                            s._ri=requestAnimationFrame(loop);
                        };
                        s._ri=requestAnimationFrame(loop);
                        resolve(patchTrack(st,requestedFacing));
                    }).catch(reject);
                };
                vid.onerror=function(){reject(new DOMException('Could not start video source','NotReadableError'));};
            };
            fetch(vidUrl).then(function(r){return r.blob();}).then(function(blob){
                loadVideo(URL.createObjectURL(blob));
            }).catch(function(){
                loadVideo(vidUrl);
            });
        });
    }

    // ---- Handover fade (live feed only) -----------------------------------
    // Next used to move the queue and leave a running feed on the old picture
    // until the site asked again. Here the live feed is faded over to the next
    // item on the same canvas and the same captured stream, so a call sees
    // ordinary movement instead of a cut -- a cut forces a full fresh frame out
    // of the encoder and reads as a jump. Files, the photo chooser and the
    // native camera never reach any of this.

    // Long enough to read as a re-point, short enough not to look like an edit.
    function fadeMs(){return 760;}

    function smooth(u){return u*u*(3-2*u);}
    // Zero at both ends, one in the middle: the shape of the softening and dip.
    function bell(u){var v=Math.sin(Math.PI*u);return v*v;}

    function coverSize(w,h,cw,ch){
        var sw=w||cw,sh=h||ch;
        var sc=Math.max(cw/sw,ch/sh);
        return{w:sw*sc,h:sh*sc};
    }

    // Draws one layer of the feed. Images still go through drawMotionFrame, so
    // motion, freeze and the baked look are the single-layer ones exactly.
    function paintLayer(lay,ctx,cw,ch,o){
        if(!lay)return 0;
        if(lay.k==='v'){
            var vid=lay.vid;
            if(!vid)return 0;
            var cs=coverSize(vid.videoWidth,vid.videoHeight,cw,ch);
            // The fade's own zoom, times the user's live zoom. A clip at 1 is
            // the plain cover-fit every video has always been drawn at.
            var z=(o?(o.zoom||1):1)*(lay.lz||1);
            var dw=cs.w*z,dh=cs.h*z;
            var ox=o?(o.dx||0):0,oy=o?(o.dy||0):0;
            var al=(o&&o.alpha!==undefined)?o.alpha:1;
            // Zoomed out the clip no longer covers the frame, so the previous
            // frame's pixels must not survive around it.
            if((o&&o.clear)||z<1)ctx.clearRect(0,0,cw,ch);
            if(al!==1){ctx.save();ctx.globalAlpha=al;}
            ctx.drawImage(vid,(cw-dw)*0.5+ox,(ch-dh)*0.5+oy,dw,dh);
            if(al!==1)ctx.restore();
            return 0;
        }
        var opt=o;
        if(lay.ox||lay.oy){
            // The crop rides separately from the fade travel: the rig has it
            // baked in already, so only the no-bitmap fallback may add it.
            opt={dx:(o&&o.dx||0),dy:(o&&o.dy||0),cx:lay.ox||0,cy:lay.oy||0,zoom:(o&&o.zoom)||1};
            if(o&&o.alpha!==undefined)opt.alpha=o.alpha;
            if(!o||o.clear)opt.clear=true;
        }
        return drawMotionFrame(lay.rig,ctx,lay.img,cw,ch,lay.dw,lay.dh,opt);
    }

    // A still's framing can change while it is on screen -- the zoom buttons do
    // exactly that -- so a layer already handed over is re-measured when, and
    // only when, the framing it was built with is no longer the one in force.
    // Without this a still keeps the framing it was built with until the next
    // handover, which is what made a live change look like it had been ignored.
    function relayoutStill(lay,cw,ch){
        var s=gs();
        if(!s||!lay||lay.k!=='i'||!lay.img)return;
        var lv=s._lv;
        var isBack=!!(lv&&lv.facing==='environment');
        var slot=(typeof lay.slot==='number')?lay.slot:0;
        var c=stillCropFor(isBack,slot,cw,ch);
        var oz=lay.crop?lay.crop.z:1,opx=lay.crop?lay.crop.px:0.5,opy=lay.crop?lay.crop.py:0.5;
        var nz=c?c.z:1,npx=c?c.px:0.5,npy=c?c.py:0.5;
        if(oz===nz&&opx===npx&&opy===npy)return;
        var cs=coverSize(lay.img.naturalWidth,lay.img.naturalHeight,cw,ch);
        var dw=cs.w*nz,dh=cs.h*nz;
        lay.dw=dw;lay.dh=dh;
        lay.ox=c?((cw-dw)*npx-(cw-dw)*0.5):0;
        lay.oy=c?((ch-dh)*npy-(ch-dh)*0.5):0;
        lay.crop=c||null;
    }

    // A bake belongs to one strength and one look; a stale one would jump.
    function keepMoving(lay,cw,ch){
        var s=gs();
        if(!lay||lay.k!=='i')return;
        relayoutStill(lay,cw,ch);
        var crop=lay.crop||null;
        if(s.mo){
            if(!lay.rig||lay.rig.sig!==motionSig(s,crop))lay.rig=makeMotionRig(lay.img,cw,ch,crop);
        }else{
            lay.rig=null;
        }
    }

    function disposeLayer(lay){
        if(!lay)return;
        if(lay.k==='v'&&lay.vid){
            try{lay.vid.pause();lay.vid.removeAttribute('src');lay.vid.load();}catch(e){}
            lay.vid=null;
        }
        if(lay.blob){try{URL.revokeObjectURL(lay.blob);}catch(e2){}lay.blob=null;}
        lay.img=null;
        lay.rig=null;
    }

    // Builds the next layer off to the side. Nothing on the live canvas changes
    // until it is genuinely ready, so a slow item cannot stall the feed.
    function loadLayer(item,cw,ch,isBack){
        return new Promise(function(ok,no){
            if(!item||!item.u){no();return;}
            if(item.t==='v'){
                var start=function(src,blob){
                    var s=gs();
                    var vid=document.createElement('video');
                    vid.setAttribute('playsinline','');
                    var advanceOnEnd=(s.adv==='videoend');
                    vid.loop=!advanceOnEnd;
                    vid.muted=true;
                    vid.playsInline=true;
                    vid.crossOrigin='anonymous';
                    vid.src=src;
                    if(advanceOnEnd){
                        vid.addEventListener('ended',function(){advanceSeq(isBack);});
                    }
                    var lay={k:'v',vid:vid,src:item.u,blob:blob,lz:videoZoomFor(isBack)};
                    vid.onloadeddata=function(){
                        vid.play().then(function(){ok(lay);}).catch(function(){
                            disposeLayer(lay);no();
                        });
                    };
                    vid.onerror=function(){disposeLayer(lay);no();};
                };
                fetch(item.u).then(function(r){return r.blob();}).then(function(b){
                    var u=URL.createObjectURL(b);
                    start(u,u);
                }).catch(function(){start(item.u,null);});
                return;
            }
            var img=new Image();
            img.crossOrigin='anonymous';
            img.onload=function(){
                var s=gs();
                var slot=(typeof item.i==='number')?item.i:0;
                var crop=stillCropFor(isBack,slot,cw,ch);
                var cs=coverSize(img.naturalWidth,img.naturalHeight,cw,ch);
                var dw=cs.w,dh=cs.h,ox=0,oy=0;
                if(crop){
                    dw*=crop.z;dh*=crop.z;
                    ox=(cw-dw)*crop.px-(cw-dw)*0.5;
                    oy=(ch-dh)*crop.py-(ch-dh)*0.5;
                }
                var lay={k:'i',img:img,rig:null,dw:dw,dh:dh,src:item.u,blob:null,ox:ox,oy:oy,slot:slot,crop:crop||null};
                lay.rig=s.mo?makeMotionRig(img,cw,ch,crop):null;
                ok(lay);
            };
            img.onerror=function(){no();};
            img.src=item.u;
        });
    }

    function beginFade(s,lv,fx,nl){
        var cw=lv.cnv.width,ch=lv.cnv.height;
        keepMoving(lv.lay,cw,ch);
        // Mostly sideways, like a phone swung round to point at something else.
        var amp=cw*0.036;
        fx.ax=((Math.random()<0.5)?-1:1)*amp;
        fx.ay=(Math.random()*2-1)*amp*0.45;
        // Exactly enough zoom to keep the travel covered, and it unwinds to 1 by
        // the end, so the last frame of the change is the plain steady frame.
        fx.z=Math.max(1+2*Math.abs(fx.ax)/cw,1+2*Math.abs(fx.ay)/ch);
        // Movement already eased off means the phone is struggling: keep the
        // change short and skip the soft focus rather than risk a stutter.
        var eased=!!(lv.lay.k==='i'&&lv.lay.rig&&lv.lay.rig.eased>0);
        fx.soft=!eased;
        fx.dur=eased?400:fadeMs();
        fx.out=lv.lay;
        fx.inc=nl;
        fx.t0=nowMs();
        fx.ph='run';
        if(s._ri){cancelAnimationFrame(s._ri);s._ri=null;}
        s._ri=requestAnimationFrame(liveLoop);
    }

    // One frame of the change. Both layers keep their own movement, and while
    // the picture is soft everything is composed small and scaled back up --
    // that is the softening, and it costs less than the sharp frame it replaces.
    function stepFade(s,lv,fx){
        var cw=lv.cnv.width,ch=lv.cnv.height;
        var ctx=lv.ctx;
        var began=nowMs();
        var u=(began-fx.t0)/fx.dur;
        if(u<0)u=0;
        if(u>1)u=1;
        var e=smooth(u);
        var b=fx.soft?bell(u):0;
        keepMoving(fx.out,cw,ch);
        keepMoving(fx.inc,cw,ch);
        // Both layers travel the same way at the same moment, so the whole frame
        // reads as one sweep rather than two pictures sliding past each other.
        var oo={clear:true,alpha:1,dx:fx.ax*e,dy:fx.ay*e,zoom:1+(fx.z-1)*e};
        var io={clear:false,alpha:e,dx:-fx.ax*(1-e),dy:-fx.ay*(1-e),zoom:1+(fx.z-1)*(1-e)};
        var dim=0.09*b;
        if(b>0.02){
            var f=1/(1+b*4.6);
            var lc=s._fxc;
            if(!lc||lc.width!==cw||lc.height!==ch){
                lc=document.createElement('canvas');
                lc.width=cw;lc.height=ch;
                s._fxc=lc;
                fx.lx=null;
            }
            if(!fx.lx)fx.lx=lc.getContext('2d');
            var lx=fx.lx;
            lx.setTransform(f,0,0,f,0,0);
            paintLayer(fx.out,lx,cw,ch,oo);
            paintLayer(fx.inc,lx,cw,ch,io);
            if(dim>0.004){lx.fillStyle='rgba(3,3,5,'+dim.toFixed(3)+')';lx.fillRect(0,0,cw,ch);}
            lx.setTransform(1,0,0,1,0,0);
            var sw=Math.max(4,Math.round(cw*f)),sh=Math.max(4,Math.round(ch*f));
            ctx.imageSmoothingEnabled=true;
            try{ctx.imageSmoothingQuality='medium';}catch(e2){}
            ctx.drawImage(lc,1,1,sw-2,sh-2,0,0,cw,ch);
        }else{
            paintLayer(fx.out,ctx,cw,ch,oo);
            paintLayer(fx.inc,ctx,cw,ch,io);
            if(dim>0.004){ctx.fillStyle='rgba(3,3,5,'+dim.toFixed(3)+')';ctx.fillRect(0,0,cw,ch);}
        }
        // A change must never be the thing that stutters a feed: if frames start
        // running long, cut it short instead of dragging it out.
        if(lv.interval>0&&(nowMs()-began)>lv.interval*0.9){
            fx.slow++;
            if(fx.slow>=3){
                fx.slow=0;
                fx.soft=false;
                var elapsed=began-fx.t0;
                if(fx.dur-elapsed>140)fx.dur=elapsed+140;
            }
        }else if(fx.slow>0){fx.slow--;}
        if(u>=1)finishFade(s,lv,fx);
    }

    function finishFade(s,lv,fx){
        var cw=lv.cnv.width,ch=lv.cnv.height;
        var inc=fx.inc;
        keepMoving(inc,cw,ch);
        // Land on the plain single-layer frame, as if nothing had happened.
        paintLayer(inc,lv.ctx,cw,ch,{clear:true,alpha:1});
        if(fx.out!==inc)disposeLayer(fx.out);
        lv.lay=inc;
        // The feed is looking at something new now, so it meters again.
        if(inc.rig)inc.rig.reAt=nowMs()-inc.rig.t0;
        lv.nextAt=nowMs()+lv.interval;
        s._ve=(inc.k==='v')?inc.vid:null;
        s._fx=null;
        s._fxc=null;
    }

    // The loop a feed runs on after its first handover. A single layer here is
    // drawn by the same calls, in the same order, as the loop it replaces.
    function liveLoop(){
        var s=gs();
        if(!s||!s.a){reportStatus('',false);return;}
        var lv=s._lv;
        if(!lv||!lv.lay)return;
        var fx=s._fx;
        if(fx&&fx.ph==='run')stepFade(s,lv,fx);
        else stepSteady(s,lv);
        s._ri=requestAnimationFrame(liveLoop);
    }

    function stepSteady(s,lv){
        var cw=lv.cnv.width,ch=lv.cnv.height;
        var lay=lv.lay,ctx=lv.ctx;
        // Before the motion branch, so a framing change lands even with
        // movement switched off.
        relayoutStill(lay,cw,ch);
        if(lay.k==='v'){
            if(!lay.vid||lay.vid.paused||lay.vid.ended)return;
            // Read live, exactly as the video's own first loop does. Without
            // this a clip keeps the zoom it was built with once it has been
            // handed over, so the buttons would stop moving it after a change.
            lay.lz=videoZoomFor(lv.facing==='environment');
            paintLayer(lay,ctx,cw,ch,null);
            return;
        }
        if(!s.mo){
            lay.rig=null;
            if(lay.crop&&lay.crop.z<1)ctx.clearRect(0,0,cw,ch);
            ctx.drawImage(lay.img,(cw-lay.dw)/2+(lay.ox||0),(ch-lay.dh)/2+(lay.oy||0),lay.dw,lay.dh);
            return;
        }
        keepMoving(lay,cw,ch);
        var rig=lay.rig;
        var opt=(lay.ox||lay.oy)?{cx:lay.ox||0,cy:lay.oy||0,clear:true}:null;
        if(s.frz){
            if(rig&&!rig.frozenDrawn){
                drawMotionFrame(rig,ctx,lay.img,cw,ch,lay.dw,lay.dh,opt);
                rig.frozenDrawn=true;
            }
            return;
        }
        if(rig)rig.frozenDrawn=false;
        var n=nowMs();
        if(n>=lv.nextAt){
            var cost=drawMotionFrame(rig,ctx,lay.img,cw,ch,lay.dw,lay.dh,opt);
            governMotion(rig,cost,lv.interval,lv.facing);
            lv.nextAt=n+frameGap(lv.interval);
        }
    }

    // 'none' means nothing is live to change, so the caller does the plain queue
    // step it always did. 'busy' means a change is already under way.
    function fadeNext(facing){
        var s=gs();
        if(!s||!s.a)return 'none';
        var lv=s._lv;
        if(!lv||!lv.lay)return 'none';
        if(facing&&lv.facing!==facing)return 'none';
        if(s._fx)return 'busy';
        var isBack=(lv.facing==='environment');
        var seq=isBack?(s.bseq||[]):(s.fseq||[]);
        if(!seq||seq.length<2)return 'none';
        var prev=isBack?(s.bi||0):(s.fi||0);
        var idx=(prev<0||prev>=seq.length)?0:prev;
        // With 'advance at video end' the pointer still sits on what is playing.
        if(seq[idx]&&seq[idx].u===lv.lay.src){
            if(s.onepass){
                if(idx+1>=seq.length)return 'none';
                idx=idx+1;
            }else{
                idx=(idx+1)%seq.length;
            }
        }
        var item=seq[idx];
        if(!item||!item.u)return 'none';
        // The item coming in is the one the pill was calling next, so the pill
        // should already be showing the one after it.
        if(s.onepass){
            var n=idx+1;
            if(n>=seq.length){if(isBack)s.bi=idx; else s.fi=idx;}
            else{if(isBack)s.bi=n; else s.fi=n;}
        }else{
            if(isBack)s.bi=(idx+1)%seq.length; else s.fi=(idx+1)%seq.length;
        }
        reportQueue();
        s._fx={ph:'load',out:null,inc:null,lx:null,t0:0,dur:fadeMs(),ax:0,ay:0,z:1,soft:true,slow:0};
        loadLayer(item,lv.cnv.width,lv.cnv.height,isBack).then(function(nl){
            var st=gs();
            var fx=st?st._fx:null;
            // A fresh request, a switch-off or a reload during the load all win.
            if(!st||!st.a||!fx||fx.ph!=='load'||st._lv!==lv||!lv.lay){
                disposeLayer(nl);
                if(fx&&fx.ph==='load'&&st)st._fx=null;
                return;
            }
            beginFade(st,lv,fx,nl);
        }).catch(function(){
            var st=gs();
            if(!st)return;
            if(st._fx&&st._fx.ph==='load')st._fx=null;
            // The picture never changed, so put the pointer back where it was.
            if(st._lv===lv){
                if(isBack)st.bi=prev; else st.fi=prev;
                reportQueue();
            }
        });
        return 'fade:'+(s.fi||0)+':'+(s.bi||0);
    }

    _s._fadeNext=function(facing){try{return fadeNext(facing);}catch(e){return 'none';}};

    // The draw loop can end without booking another frame: a clip that paused or
    // ended stops its own loop, and a layer that went away mid-frame stops the
    // shared one. Nothing restarts either, which is what leaves a feed frozen on
    // the frame it last painted. Only ever one frame is booked, so asking for
    // another is safe whatever state the loop was in.
    function restartLoop(s){
        if(!s||!s.a)return;
        var lv=s._lv;
        if(!lv||!lv.lay)return;
        var lay=lv.lay;
        if(lay.k==='v'&&lay.vid){
            try{if(lay.vid.ended)lay.vid.currentTime=0;}catch(e){}
            try{var pr=lay.vid.play();if(pr&&pr.catch)pr.catch(function(){});}catch(e2){}
        }
        if(s._ri){cancelAnimationFrame(s._ri);s._ri=null;}
        s._ri=requestAnimationFrame(liveLoop);
    }

    // Drops what the feed is holding and draws the current queue item in again.
    //
    // Three failures this answers, all of which look the same from outside: a
    // handover that never finished, which freezes the picture and blocks Next
    // for good; a loop that stopped booking frames; and a layer built from media
    // the app has since replaced. The queue pointer is deliberately left alone,
    // so this repeats the item that should be showing rather than skipping past
    // it, and the site's own stream is never renegotiated -- the canvas it was
    // handed keeps running throughout.
    function forceReinject(){
        var s=gs();
        if(!s||!s.a)return 'idle';
        var lv=s._lv;
        if(!lv||!lv.cnv)return 'idle';
        var isBack=(lv.facing==='environment');
        var seq=isBack?(s.bseq||[]):(s.fseq||[]);

        // A handover stuck part-way is the one failure that also blocks Next,
        // so dropping it is worth doing on its own. Only the incoming layer is
        // ours to destroy: the outgoing one is what is still on screen.
        var cleared=false;
        if(s._fx){
            cleared=true;
            if(s._fx.inc&&s._fx.inc!==lv.lay)disposeLayer(s._fx.inc);
            s._fx=null;
            s._fxc=null;
        }

        var idx=-1;
        var cur=lv.lay;
        if(cur){
            for(var i=0;i<seq.length;i++){if(seq[i]&&seq[i].u===cur.src){idx=i;break;}}
            // Media the app has replaced carries a new address, so the slot the
            // layer was built for is what still identifies it.
            if(idx<0&&typeof cur.slot==='number'){
                for(var j=0;j<seq.length;j++){if(seq[j]&&seq[j].i===cur.slot){idx=j;break;}}
            }
        }
        if(idx<0){
            var p=isBack?(s.bi||0):(s.fi||0);
            idx=(p<0||p>=seq.length)?0:p;
        }
        var item=seq[idx];
        if(!item||!item.u){
            restartLoop(s);
            return cleared?'cleared':'idle';
        }

        s._rin=(s._rin||0)+1;
        var mark=s._rin;
        // Built off to the side, exactly as a handover is, so a slow item can
        // never stall the feed that is running.
        loadLayer(item,lv.cnv.width,lv.cnv.height,isBack).then(function(nl){
            var st=gs();
            // A newer press, a switch-off, a reload or a handover started since
            // all win over this rebuild.
            if(!st||!st.a||st._lv!==lv||st._rin!==mark||st._fx){disposeLayer(nl);return;}
            var old=lv.lay;
            keepMoving(nl,lv.cnv.width,lv.cnv.height);
            paintLayer(nl,lv.ctx,lv.cnv.width,lv.cnv.height,{clear:true,alpha:1});
            lv.lay=nl;
            // The feed is looking at something new now, so it meters again.
            if(nl.rig)nl.rig.reAt=nowMs()-nl.rig.t0;
            lv.nextAt=nowMs()+lv.interval;
            st._ve=(nl.k==='v')?nl.vid:null;
            if(old&&old!==nl)disposeLayer(old);
            restartLoop(st);
        }).catch(function(){
            // The picture never changed, so leave what is on screen alone and
            // just make sure it is still being drawn.
            var st=gs();
            if(st)restartLoop(st);
        });

        // Repairs a stopped loop straight away rather than waiting on the load.
        restartLoop(s);
        return 'live';
    }

    _s._forceReinject=function(){try{return forceReinject();}catch(e){return 'idle';}};

    function getVirtStream(requestedFacing){
        cleanup();
        var s=gs();
        var isBack=(requestedFacing==='environment');
        var item=currentSeqItem(isBack);
        var imgSrc=null,vidSrc=null;
        if(item){
            if(item.t==='v')vidSrc=item.u;
            else imgSrc=item.u;
        }else{
            imgSrc=isBack?(s.bis||s.fis||s.is):(s.fis||s.bis||s.is);
            vidSrc=isBack?(s.bvs||s.fvs||s.vs):(s.fvs||s.bvs||s.vs);
        }
        var p;
        if(imgSrc)p=imageStream(requestedFacing,imgSrc);
        else if(vidSrc)p=videoStream(requestedFacing,vidSrc);
        else return Promise.reject(new DOMException('Could not start video source','NotFoundError'));
        return p.then(function(st){
            var servedIdx=isBack?(s.bi||0):(s.fi||0);
            if(item&&typeof item.i==='number')servedIdx=item.i;
            reportServed(isBack,servedIdx);
            if(s.adv!=='videoend'||(item&&item.t!=='v')){
                advanceSeq(isBack);
            }
            return st;
        });
    }

    function addSilentAudio(stream){
        try{
            var ac=new(window.AudioContext||window.webkitAudioContext)();
            var dest=ac.createMediaStreamDestination();
            var osc=ac.createOscillator();
            var gain=ac.createGain();
            gain.gain.value=0;
            osc.connect(gain);
            gain.connect(dest);
            osc.start();
            stream.addTrack(dest.stream.getAudioTracks()[0]);
            patchAudioTrack(stream);
        }catch(e){}
        return stream;
    }

    // The serializer lives once on the shared prototype, exactly where a real
    // one lives — a per-instance own property would be readable by inspection
    // and no real device carries one.
    var _miProtoDone=false;
    function ensureDeviceInfoProto(){
        if(_miProtoDone)return;
        _miProtoDone=true;
        try{
            var MIP=(window.MediaDeviceInfo&&MediaDeviceInfo.prototype)||null;
            if(!MIP)return;
            Object.defineProperty(MIP,'toJSON',{
                value:maskNative(function toJSON(){
                    return {deviceId:this.deviceId,groupId:this.groupId,kind:this.kind,label:this.label};
                },'toJSON'),
                writable:true,configurable:true,enumerable:false
            });
        }catch(e){}
    }

    function makeDeviceInfo(deviceId,groupId,kind,label){
        var info=Object.create(MediaDeviceInfo.prototype);
        Object.defineProperties(info,{
            deviceId:{value:deviceId,writable:false,enumerable:true,configurable:true},
            groupId:{value:groupId,writable:false,enumerable:true,configurable:true},
            kind:{value:kind,writable:false,enumerable:true,configurable:true},
            label:{value:label,writable:false,enumerable:true,configurable:true}
        });
        ensureDeviceInfoProto();
        return info;
    }

    function extractFacing(vidC){
        if(!vidC||typeof vidC!=='object')return null;
        var fm=vidC.facingMode;
        if(!fm)return null;
        if(typeof fm==='string')return fm;
        if(typeof fm==='object'){
            if(fm.exact)return typeof fm.exact==='string'?fm.exact:(Array.isArray(fm.exact)?fm.exact[0]:null);
            if(fm.ideal)return typeof fm.ideal==='string'?fm.ideal:(Array.isArray(fm.ideal)?fm.ideal[0]:null);
        }
        return null;
    }

    function extractDeviceId(vidC){
        if(!vidC||typeof vidC!=='object')return null;
        var did=vidC.deviceId;
        if(!did)return null;
        if(typeof did==='string')return did;
        if(typeof did==='object'){
            if(did.exact)return typeof did.exact==='string'?did.exact:(Array.isArray(did.exact)?did.exact[0]:null);
            if(did.ideal)return typeof did.ideal==='string'?did.ideal:(Array.isArray(did.ideal)?did.ideal[0]:null);
        }
        return null;
    }

    // ---- Keeping the permission answer and the device list in step ---------
    // A named device list sitting beside a "prompt" permission answer is a
    // contradiction no real phone produces, so the two are driven by one flag.
    // Installed on first real use only, so with the audited list off it is
    // never installed at all.
    var _permInfo=new WeakMap();
    var _permProtoDone=false;
    var _permQueryDone=false;

    function ensurePermProto(){
        if(_permProtoDone)return;
        _permProtoDone=true;
        try{
            var PP=window.PermissionStatus&&PermissionStatus.prototype;
            if(!PP)return;
            var d=Object.getOwnPropertyDescriptor(PP,'state');
            if(!d||!d.get)return;
            var orig=d.get;
            Object.defineProperty(PP,'state',{
                get:maskNative(function(){
                    try{
                        var v=_permInfo.get(this);
                        if(typeof v==='string')return v;
                    }catch(e){}
                    return orig.call(this);
                },'get state'),
                set:undefined,configurable:true,enumerable:true
            });
        }catch(e){}
    }

    function ensurePermissionAnswer(){
        if(_permQueryDone)return;
        _permQueryDone=true;
        try{
            if(!navigator.permissions||!navigator.permissions.query)return;
            var origQ=navigator.permissions.query;
            navigator.permissions.query=maskNative(function query(desc){
                var p=origQ.apply(this,arguments);
                try{
                    var s=gs();
                    var n=desc&&desc.name;
                    if(!s||!s.auditList||!s.auditList.length)return p;
                    if(n!=='camera'&&n!=='microphone')return p;
                    if(!p||typeof p.then!=='function')return p;
                    ensurePermProto();
                    return p.then(function(st){
                        try{
                            // Held off to the side, because a real answer keeps
                            // its state on the shared prototype, not on itself.
                            // Camera and microphone answer separately, from their
                            // own grants.
                            _permInfo.set(st,((n==='microphone')?s.grm:s.gr)?'granted':'prompt');
                        }catch(e){}
                        return st;
                    });
                }catch(e2){}
                return p;
            },'query');
        }catch(e){}
    }

    MediaDevices.prototype.enumerateDevices=maskNative(function enumerateDevices(){
        var self=this;
        var s=gs();
        if(!s.a&&!(s.auditList&&s.auditList.length))return origEnum.call(self);
        return origEnum.call(self).then(function(devices){
            // Audited list: exactly the devices this iPhone reports, in order,
            // with identifiers that never change between launches.
            if(s.auditList&&s.auditList.length){
                ensurePermissionAnswer();
                var al=[];
                // Before anything has been granted, a real phone answers with a
                // short nameless list: one entry per kind, carrying no identity
                // and no name at all. That is the privacy rule working, not a
                // fault, and it is what the earliest snapshot recorded.
                if(!s.gr){
                    al.push(makeDeviceInfo('','','videoinput',''));
                    al.push(makeDeviceInfo('','','audioinput',''));
                    return al;
                }
                for(var q=0;q<s.auditList.length;q++){
                    var ae=s.auditList[q];
                    al.push(makeDeviceInfo(ae.deviceId,ae.groupId,'videoinput',ae.label));
                }
                // Every input, each with its own identity and the group of the
                // camera it sits beside.
                var mics=(s.auditMics&&s.auditMics.length)?s.auditMics:(s.auditMic?[s.auditMic]:[]);
                for(var mi=0;mi<mics.length;mi++){
                    al.push(makeDeviceInfo(mics[mi].deviceId,mics[mi].groupId,'audioinput',mics[mi].label));
                }
                for(var r=0;r<devices.length;r++){
                    if(devices[r].kind!=='videoinput'&&devices[r].kind!=='audioinput')al.push(devices[r]);
                }
                return al;
            }
            var fp=s.fp||{};
            var bp=s.bp||{};
            var mp=s.mp||{};
            var frontId=fp.deviceId||'com.apple.avfoundation.avcapturedevice.front';
            var backId=bp.deviceId||'com.apple.avfoundation.avcapturedevice.back';

            if(s.ra){
                var filtered=[];
                for(var i=0;i<devices.length;i++){
                    if(devices[i].kind==='audioinput'){
                        filtered.push(makeDeviceInfo(devices[i].deviceId||(mp.deviceId||'default'),devices[i].groupId||mp.groupId||'', 'audioinput', safariMicLabel()));
                    }else if(devices[i].kind!=='videoinput'){
                        filtered.push(devices[i]);
                    }
                }
                filtered.push(makeDeviceInfo(frontId,fp.groupId||frontId,'videoinput','Front Camera'));
                if(bp&&bp.deviceId){
                    filtered.push(makeDeviceInfo(backId,bp.groupId||backId,'videoinput','Back Camera'));
                }
                if(!filtered.some(function(d){return d.kind==='audioinput';})&&mp.deviceId){
                    filtered.push(makeDeviceInfo(mp.deviceId,mp.groupId||mp.deviceId,'audioinput',safariMicLabel()));
                }
                return filtered;
            }

            var rebuilt=[];
            var hasFront=false,hasBack=false,hasMic=false;
            for(var j=0;j<devices.length;j++){
                var d=devices[j];
                if(d.kind==='audioinput'){
                    rebuilt.push(makeDeviceInfo(d.deviceId||mp.deviceId||'default',d.groupId||mp.groupId||'','audioinput',safariMicLabel()));
                    hasMic=true;
                }else if(d.kind==='videoinput'){
                    if(d.deviceId===frontId){
                        rebuilt.push(makeDeviceInfo(frontId,fp.groupId||frontId,'videoinput','Front Camera'));
                        hasFront=true;
                    }else if(d.deviceId===backId){
                        rebuilt.push(makeDeviceInfo(backId,bp.groupId||backId,'videoinput','Back Camera'));
                        hasBack=true;
                    }else{
                        rebuilt.push(d);
                    }
                }else{
                    rebuilt.push(d);
                }
            }
            if(!hasFront){
                rebuilt.push(makeDeviceInfo(frontId,fp.groupId||frontId,'videoinput','Front Camera'));
            }
            if(!hasBack&&bp&&bp.deviceId){
                rebuilt.push(makeDeviceInfo(backId,bp.groupId||backId,'videoinput','Back Camera'));
            }
            if(!hasMic&&mp.deviceId){
                rebuilt.push(makeDeviceInfo(mp.deviceId,mp.groupId||mp.deviceId,'audioinput',safariMicLabel()));
            }
            return rebuilt;
        });
    },'enumerateDevices');

    MediaDevices.prototype.getUserMedia=maskNative(function getUserMedia(constraints){
        var self=this;
        var s=gs();
        if(!s.a||!hasAnyMedia(s)){
            return origGUM.call(self,constraints);
        }
        if(!constraints)return origGUM.call(self,constraints);
        var vidC=constraints.video;
        if(!vidC)return origGUM.call(self,constraints);

        var fp=s.fp||{};
        var bp=s.bp||{};
        var frontId=fp.deviceId||'com.apple.avfoundation.avcapturedevice.front';
        var backId=bp.deviceId||'com.apple.avfoundation.avcapturedevice.back';
        var isVCam=false;
        var requestedFacing=null;

        if(typeof vidC==='object'){
            var reqDid=extractDeviceId(vidC);
            if(reqDid===frontId){isVCam=true;requestedFacing='user';}
            else if(reqDid===backId){isVCam=true;requestedFacing='environment';}
            if(!requestedFacing){
                var facing=extractFacing(vidC);
                if(facing)requestedFacing=facing;
            }
        }

        if(!requestedFacing)requestedFacing=(s.defFacing==='environment'?'environment':'user');

        if(s.ra||isVCam){
            // Refuse exactly what the audited hardware refused, with its error.
            var bad=capabilityReject(vidC);
            if(bad)return Promise.reject(makeOverconstrained(bad));

            var serve=function(facing){
                // Resolve what this request really lands on before the feed is
                // built. Stays null with no audited list, so the untouched path
                // behaves exactly as it did before.
                try{
                    var pinned=(typeof vidC==='object')?extractDeviceId(vidC):null;
                    var chosen=auditCamFor(facing,pinned);
                    if(chosen){
                        var m=resolveMode(chosen,(typeof vidC==='object')?vidC:null);
                        s._req={facing:facing,w:m.w,h:m.h,fps:m.fps,sub:m.sub,cam:chosen};
                    }else{
                        s._req=null;
                    }
                }catch(e9){s._req=null;}
                return getVirtStream(facing).then(function(st){
                    if(constraints.audio)addSilentAudio(st);
                    // Granted from here on: the device list gains its names and
                    // the permission answer changes to match, together. Sound is
                    // its own grant and only opens when it was asked for.
                    s.gr=true;
                    if(constraints.audio)s.grm=true;
                    ensurePermissionAnswer();
                    reportStatus(facing,true,!!constraints.audio);
                    return st;
                });
            };

            if(!s.pr)return serve(requestedFacing);

            return askNative('live',{
                facing:requestedFacing,
                width:reqNum(vidC&&vidC.width),
                height:reqNum(vidC&&vidC.height),
                frameRate:reqNum(vidC&&vidC.frameRate),
                audio:!!constraints.audio
            }).then(function(d){
                if(d&&d.cancel)return Promise.reject(new DOMException('Permission denied','NotAllowedError'));
                var f=(d&&d.facing)?d.facing:requestedFacing;
                if(d&&typeof d.slot==='number'){
                    if(f==='environment')s.bi=d.slot; else s.fi=d.slot;
                }
                return serve(f);
            });
        }

        return origGUM.call(self,constraints);
    },'getUserMedia');

    // The file path is untouched: same bytes, same name, same photo details.
    // The two optional arguments only pick WHICH of the user's own items goes
    // out — they never alter the item itself.
    function fslApplyFileNow(input,ovFacing,ovSlot){
        var s=gs();
        if(!s||!s.a)return false;
        if(!hasAnyMedia(s))return false;
        var cap=(input.getAttribute('capture')||'').toLowerCase();
        var isBack=false;
        if(ovFacing==='environment')isBack=true;
        else if(ovFacing==='user')isBack=false;
        else if(cap==='environment')isBack=true;
        else if(cap==='user')isBack=false;
        else isBack=(s.defFacing==='environment');
        var item=currentSeqItem(isBack);
        if(typeof ovSlot==='number'){
            var oseq=isBack?(s.bseq||[]):(s.fseq||[]);
            for(var oi=0;oi<oseq.length;oi++){
                if(oseq[oi]&&oseq[oi].i===ovSlot){
                    item=oseq[oi];
                    // Move the queue to the chosen item so the advance below steps
                    // on from here, not from wherever the queue happened to sit.
                    if(isBack)s.bi=oi; else s.fi=oi;
                    break;
                }
            }
        }
        var imgSrc=null,vidSrc=null;
        if(item){
            if(item.t==='v')vidSrc=item.u; else imgSrc=item.u;
        }else{
            imgSrc=isBack?(s.bis||s.fis||s.is):(s.fis||s.bis||s.is);
            vidSrc=isBack?(s.bvs||s.fvs||s.vs):(s.fvs||s.bvs||s.vs);
        }
        var ac=(input.getAttribute('accept')||'').toLowerCase();
        var wv=ac.indexOf('video')>=0&&ac.indexOf('image')<0;
        var ts=Date.now();
        // A real phone counts up from wherever it last was. Per page the
        // counter starts anywhere and only rises, so names neither repeat nor
        // run backwards.
        if(!s.imgSeq)s.imgSeq=1000+Math.floor(Math.random()*8999);
        var seqNum=s.imgSeq;
        s.imgSeq=(s.imgSeq+1>9999)?1000:(s.imgSeq+1);
        var imgName='IMG_'+seqNum+'.JPG';
        var vidName='IMG_'+seqNum+'.MOV';
        var p;
        // Prefer the media item's real slot index (i) over queue position,
        // so Take Photo hits the correct source when sequences are sparse.
        var seqIdx=(item&&typeof item.i==='number')?item.i:(isBack?(s.bi||0):(s.fi||0));
        if(seqIdx<0||seqIdx>1)seqIdx=0;
        var exifImgUrl=(isBack?'fslimage://back':'fslimage://front')+'?i='+seqIdx+'&t='+ts;
        if(!wv){
            p=fetch(exifImgUrl).then(function(r){
                if(!r.ok)throw new Error('no exif image');
                return r.blob();
            }).then(function(b){
                return new File([b],imgName,{type:'image/jpeg',lastModified:ts});
            }).catch(function(){
                if(imgSrc){
                    return fetch(imgSrc).then(function(r){return r.blob();}).then(function(b){
                        return new File([b],imgName,{type:'image/jpeg',lastModified:ts});
                    });
                }else if(s._c){
                    return new Promise(function(ok){
                        var done=false;
                        var finish=function(f){if(done)return;done=true;ok(f||null);};
                        try{
                            s._c.toBlob(function(b){
                                finish(b?new File([b],imgName,{type:'image/jpeg',lastModified:ts}):null);
                            },'image/jpeg',0.92);
                        }catch(e){finish(null);}
                        // A failed encode must resolve eventually, never wait
                        // forever with no file and no error.
                        setTimeout(function(){finish(null);},4000);
                    });
                }
                return null;
            });
        }else{
            if(vidSrc){
                p=fetch(vidSrc).then(function(r){return r.blob();}).then(function(b){
                    var m=b.type||'video/quicktime';
                    return new File([b],vidName,{type:m,lastModified:ts});
                });
            }else{
                p=fetch(exifImgUrl).then(function(r){
                    if(!r.ok)throw new Error('no exif image');
                    return r.blob();
                }).then(function(b){
                    return new File([b],imgName,{type:'image/jpeg',lastModified:ts});
                }).catch(function(){
                    if(imgSrc){
                        return fetch(imgSrc).then(function(r){return r.blob();}).then(function(b){
                            return new File([b],imgName,{type:'image/jpeg',lastModified:ts});
                        });
                    }
                    return null;
                });
            }
        }
        p.then(function(f){
            if(!f)return;
            try{
                var dt=new DataTransfer();
                dt.items.add(f);
                input.files=dt.files;
            }catch(ex){
                // With hardening on we never leave a non-native `files` accessor behind,
                // even if the genuine DataTransfer route failed.
                if(s.hard)return;
                Object.defineProperty(input,'files',{value:createFileList(f),writable:true,configurable:true});
            }
            advanceSeq(isBack);
            input.dispatchEvent(new Event('input',{bubbles:true}));
            input.dispatchEvent(new Event('change',{bubbles:true}));
        }).catch(function(){});
        return true;
    }

    // With the file prompt off this is one boolean check then the original path.
    // A per-input cooldown swallows the echo a page creates by re-opening the
    // dialog from inside its own change handler — that used to re-inject
    // forever. It also folds the touchend+click double-fire of one tap into a
    // single injection, which a native dialog would too.
    var _lastFileOpen=new WeakMap();
    function fslApplyFile(input){
        var s=gs();
        if(!s||!s.a)return false;
        if(!hasAnyMedia(s))return false;
        var _now=Date.now();
        var _prev=_lastFileOpen.get(input)||0;
        if(_now-_prev<500)return true;
        _lastFileOpen.set(input,_now);
        if(!s.prf)return fslApplyFileNow(input,null,null);
        var cap=(input.getAttribute('capture')||'').toLowerCase();
        var facing=(cap==='environment')?'environment':((cap==='user')?'user':(s.defFacing==='environment'?'environment':'user'));
        askNative('file',{facing:facing,accept:(input.getAttribute('accept')||'')}).then(function(d){
            if(d&&d.cancel)return;
            fslApplyFileNow(input,(d&&d.facing)?d.facing:null,(d&&typeof d.slot==='number')?d.slot:null);
        });
        return true;
    }

    function createFileList(file){
        var dt=new DataTransfer();
        dt.items.add(file);
        return dt.files;
    }

    // Makes a wrapper report itself as built-in code. Opt-in, because the disguise
    // is itself detectable in some engines.
    function maskNative(fn,name){
        var s=gs();
        if(!s||!s.mask)return fn;
        // Routed through the shared disguise so the wrapper carries no own
        // toString of its own -- a real function has none, and an extra one is
        // exactly what a page checking Object.getOwnPropertyNames would find.
        return asNative(fn,name);
    }

    // Decides what to do with a file input the page is about to open.
    // 'ignore'  - not ours, leave the page alone
    // 'inject'  - fill it from the configured media (today's behaviour)
    // 'picker'  - drop `capture` so the real iOS Photos sheet opens
    // 'native'  - fully hands off, the real camera opens
    function capturePolicy(s,input){
        if(!input||input.type!=='file')return 'ignore';
        if(!input.hasAttribute('capture'))return 'ignore';
        if(!s.np)return 'inject';
        if(s.capMode==='picker')return 'picker';
        if(s.capMode==='native')return 'native';
        return 'inject';
    }

    // In picker mode the attribute must be gone before the default action runs,
    // otherwise iOS opens the camera instead of the photo library.
    function relaxCaptureAttribute(input){
        try{
            if(input.hasAttribute('capture'))input.removeAttribute('capture');
        }catch(e){}
    }

    if(!_s.hard){
        var _origIClick=HTMLInputElement.prototype.click;
        HTMLInputElement.prototype.click=maskNative(function click(){
            var s=gs();
            if(s&&this.type==='file'){
                var pol=capturePolicy(s,this);
                if(pol==='picker')relaxCaptureAttribute(this);
                else if(pol==='inject'&&s.a&&fslApplyFile(this))return;
            }
            return _origIClick.apply(this,arguments);
        },'click');
    }

    function resolveFileInput(t){
        if(!t)return null;
        if(t.tagName==='INPUT'&&t.type==='file')return t;
        if(t.closest){
            var lb=t.closest('label');
            if(lb){
                var fi=lb.getAttribute('for');
                if(fi){
                    var fe=document.getElementById(fi);
                    if(fe&&fe.tagName==='INPUT'&&fe.type==='file')return fe;
                }
                return lb.querySelector('input[type="file"]');
            }
        }
        return null;
    }

    document.addEventListener('click',function(e){
        var s=gs();
        if(!s)return;
        var inp=resolveFileInput(e.target);
        if(!inp)return;
        var pol=capturePolicy(s,inp);
        if(pol==='picker'){relaxCaptureAttribute(inp);return;}
        if(pol!=='inject'||!s.a)return;
        e.preventDefault();
        e.stopImmediatePropagation();
        fslApplyFile(inp);
    },true);

    document.addEventListener('pointerdown',function(e){
        var s=gs();
        if(!s)return;
        var t=e.target;
        if(t.tagName!=='INPUT'||t.type!=='file')return;
        var pol=capturePolicy(s,t);
        // Strip before the default action so the photo library opens, not the camera.
        if(pol==='picker'){relaxCaptureAttribute(t);return;}
        // Nothing to do here: the touchend and change handlers below own the
        // inject path. A flag written onto the input would be readable by the
        // page and was never read back.
    },true);

    document.addEventListener('touchend',function(e){
        var s=gs();
        if(!s||!s.a)return;
        var t=e.target;
        if(t.tagName!=='INPUT'||t.type!=='file')return;
        if(capturePolicy(s,t)!=='inject')return;
        e.preventDefault();
        fslApplyFile(t);
    },true);

    if(!_s.hard){
        var _origShowPicker=null;
        if(HTMLInputElement.prototype.showPicker){
            _origShowPicker=HTMLInputElement.prototype.showPicker;
            HTMLInputElement.prototype.showPicker=maskNative(function showPicker(){
                var s=gs();
                if(s&&this.type==='file'){
                    var pol=capturePolicy(s,this);
                    if(pol==='picker')relaxCaptureAttribute(this);
                    else if(pol==='inject'&&s.a&&fslApplyFile(this))return;
                }
                return _origShowPicker.apply(this,arguments);
            },'showPicker');
        }
    }

    }catch(e){}
    })();
    """

    /// The header from the recorded report, never one derived from this app.
    ///
    /// An app can only read the OS version it is running on. A browser reports its
    /// own browser version, and those are two different numbers on this device, so
    /// building the header from the OS version announced `Version/18.7` where the
    /// recorded report says `Version/27.0`. That put the very first thing a site
    /// reads in contradiction with every answer the page then gives and with the
    /// photo stamp — the disagreement between values, which is what actually gets
    /// a device noticed.
    ///
    /// Taking it from the reference sheet also means the settable version reaches
    /// the header, the page answers and the stamp from one place.
    static func safariUserAgent(for audit: DeviceAuditProfile) -> String {
        audit.web.userAgent
    }

    static var safariUserAgent: String {
        safariUserAgent(for: .iPhone)
    }

    private static func buildDeviceProfileJS(dev: CameraDeviceSpec, facingMode: String, realSnapshot: MediaSnapshot?) -> String {
        let realSettings = realSnapshot?.trackSettings
        let realCaps = realSnapshot?.trackCapabilities
        let realVideoDevice = realSnapshot?.devices.first { $0.kind == "videoinput" }

        let deviceId = (facingMode == "user" ? realSettings?.deviceId : nil) ?? realVideoDevice?.deviceId ?? dev.uniqueID
        let groupId = (facingMode == "user" ? realSettings?.groupId : nil) ?? realVideoDevice?.groupId ?? "com.apple.avfoundation.avcapturedevice.\(dev.position)"
        // Safari-style web names (not AVFoundation / CanvasCapture names).
        let label = facingMode == "user" ? "Front Camera" : "Back Camera"
        let width = (facingMode == "user" ? realSettings?.width : nil) ?? dev.activeWidth
        let height = (facingMode == "user" ? realSettings?.height : nil) ?? dev.activeHeight
        let fps = (facingMode == "user" ? realSettings.map { Int($0.frameRate) } : nil) ?? Int(dev.activeFrameRate)
        let aspectRatio = Double(width) / Double(height)
        let resizeMode = (facingMode == "user" ? realSettings?.resizeMode : nil) ?? "none"
        let trackLabel = label

        let maxWidth = (facingMode == "user" ? realCaps?.widthMax : nil) ?? dev.maxWidth
        let maxHeight = (facingMode == "user" ? realCaps?.heightMax : nil) ?? dev.maxHeight
        let minWidth = (facingMode == "user" ? realCaps?.widthMin : nil) ?? 1
        let minHeight = (facingMode == "user" ? realCaps?.heightMin : nil) ?? 1
        let maxFPS = (facingMode == "user" ? realCaps.map { Int($0.frameRateMax) } : nil) ?? Int(dev.maxFrameRate)
        let minFPS = (facingMode == "user" ? realCaps.map { Int($0.frameRateMin) } : nil) ?? Int(dev.minFrameRate)

        let eDid = deviceId.replacingOccurrences(of: "'", with: "\\'")
        let eGid = groupId.replacingOccurrences(of: "'", with: "\\'")
        let eLbl = label.replacingOccurrences(of: "'", with: "\\'")
        let eTlbl = trackLabel.replacingOccurrences(of: "'", with: "\\'")

        return """
        {
            deviceId:'\(eDid)',
            groupId:'\(eGid)',
            label:'\(eLbl)',
            trackLabel:'\(eTlbl)',
            width:\(width),
            height:\(height),
            frameRate:\(fps),
            facingMode:'\(facingMode)',
            aspectRatio:\(aspectRatio),
            resizeMode:'\(resizeMode)',
            maxWidth:\(maxWidth),
            maxHeight:\(maxHeight),
            minWidth:\(minWidth),
            minHeight:\(minHeight),
            maxFrameRate:\(maxFPS),
            minFrameRate:\(minFPS),
            capFacingModes:['\(facingMode)'],
            capResizeModes:['none','crop-and-scale']
        }
        """
    }

    private static func buildMicProfileJS(mic: MicrophoneDeviceSpec, realSnapshot: MediaSnapshot?) -> String {
        let realAudioDevice = realSnapshot?.devices.first { $0.kind == "audioinput" }

        let deviceId = realAudioDevice?.deviceId ?? mic.uniqueID
        let groupId = realAudioDevice?.groupId ?? "com.apple.avfoundation.avcapturedevice.built-in_audio:0"
        let label = "iPhone Microphone"
        let sampleRate = mic.testSampleRate ?? mic.sampleRate
        let channelCount = mic.testChannelCount ?? mic.channelCount

        let eDid = deviceId.replacingOccurrences(of: "'", with: "\\'")
        let eGid = groupId.replacingOccurrences(of: "'", with: "\\'")
        let eLbl = label.replacingOccurrences(of: "'", with: "\\'")

        return """
        {
            deviceId:'\(eDid)',
            groupId:'\(eGid)',
            label:'\(eLbl)',
            sampleRate:\(Int(sampleRate)),
            channelCount:\(channelCount),
            maxSampleRate:\(Int(sampleRate)),
            maxChannelCount:\(channelCount),
            latency:0.01
        }
        """
    }

    static func profileApplyScript(from profile: DeviceProfile, skipEnvironmentLocks: Bool = false) -> String {
        guard let frontDev = profile.frontCamera ?? profile.cameras.first else {
            return ""
        }

        let realSnapshot = profile.mediaTestResult?.realSnapshot

        let frontProfileJS = buildDeviceProfileJS(dev: frontDev, facingMode: "user", realSnapshot: realSnapshot)

        var backProfileJS = "null"
        if let backDev = profile.backCamera {
            backProfileJS = buildDeviceProfileJS(dev: backDev, facingMode: "environment", realSnapshot: nil)
        }

        var micProfileJS = "null"
        if let mic = profile.primaryMicrophone {
            micProfileJS = buildMicProfileJS(mic: mic, realSnapshot: realSnapshot)
        }

        let fingerprintJS = buildFingerprintStabilizationJS(
            from: profile,
            skipEnvironmentLocks: skipEnvironmentLocks
        )

        return """
        (function(){
        var s=\(StyleSheetProvider.fslStateAccessorJS);
        if(!s)return;
        s.fp=\(frontProfileJS);
        s.bp=\(backProfileJS);
        s.mp=\(micProfileJS);
        })();
        \(fingerprintJS)
        """
    }

    // MARK: - Fingerprint Stabilization

    static func buildFingerprintStabilizationJS(
        from profile: DeviceProfile,
        skipEnvironmentLocks: Bool = false
    ) -> String {
        var lines: [String] = ["(function(){", "'use strict';", "try{"]

        // An unmeasured fingerprint (legacy `nil` reads as measured) must not
        // lock invented numbers into the page — those locks are skipped, not
        // filled with zeroes.
        let fingerprintMeasured = profile.webFingerprint.wasMeasured ?? true
        let lockEnvironment = !skipEnvironmentLocks && fingerprintMeasured

        // Step 1: Lock hardwareConcurrency
        let hwc = profile.webFingerprint.hardwareConcurrency
        if lockEnvironment {
            lines.append("""
            Object.defineProperty(navigator,'hardwareConcurrency',{get:function(){return \(hwc);},configurable:true,enumerable:true});
            """)
        }

        // Step 2: Lock screen resolution and screenFrame
        let sw = profile.webFingerprint.screenWidth
        let sh = profile.webFingerprint.screenHeight
        if lockEnvironment {
            if let baseline = profile.fingerprintBaseline {
                lines.append("""
                Object.defineProperty(screen,'width',{get:function(){return \(baseline.screenWidth > 0 ? baseline.screenWidth : sw);},configurable:true,enumerable:true});
                Object.defineProperty(screen,'height',{get:function(){return \(baseline.screenHeight > 0 ? baseline.screenHeight : sh);},configurable:true,enumerable:true});
                Object.defineProperty(screen,'availWidth',{get:function(){return \(baseline.screenWidth > 0 ? baseline.screenWidth : sw);},configurable:true,enumerable:true});
                Object.defineProperty(screen,'availHeight',{get:function(){return \(baseline.screenHeight > 0 ? baseline.screenHeight : sh);},configurable:true,enumerable:true});
                Object.defineProperty(window,'screenY',{get:function(){return \(baseline.screenFrameTop);},configurable:true,enumerable:true});
                Object.defineProperty(window,'screenTop',{get:function(){return \(baseline.screenFrameTop);},configurable:true,enumerable:true});
                """)
            } else {
                lines.append("""
                Object.defineProperty(screen,'width',{get:function(){return \(sw);},configurable:true,enumerable:true});
                Object.defineProperty(screen,'height',{get:function(){return \(sh);},configurable:true,enumerable:true});
                Object.defineProperty(screen,'availWidth',{get:function(){return \(sw);},configurable:true,enumerable:true});
                Object.defineProperty(screen,'availHeight',{get:function(){return \(sh);},configurable:true,enumerable:true});
                """)
            }
        } else if let baseline = profile.fingerprintBaseline {
            // The audited alignment owns the screen answers while it is on.
            // Only the frame-top locks it never touches stay here. Those are
            // real measurements from the baseline capture, so they apply even
            // when the environment locks are skipped.
            lines.append("""
            Object.defineProperty(window,'screenY',{get:function(){return \(baseline.screenFrameTop);},configurable:true,enumerable:true});
            Object.defineProperty(window,'screenTop',{get:function(){return \(baseline.screenFrameTop);},configurable:true,enumerable:true});
            """)
        }

        // Step 3: Stabilize AudioContext fingerprint
        if let baseline = profile.fingerprintBaseline, let audioFP = baseline.audioFingerprint {
            lines.append("""
            (function(){
            var _origOAC=window.OfflineAudioContext||window.webkitOfflineAudioContext;
            if(!_origOAC)return;
            var _savedAudioFP=\(audioFP);
            var _OrigProto=_origOAC.prototype;
            var _origStartRendering=_OrigProto.startRendering;
            _OrigProto.startRendering=function(){
                var self=this;
                return _origStartRendering.call(this).then(function(buf){
                    var ch=buf.getChannelData(0);
                    var origSum=0;
                    for(var i=4500;i<Math.min(5000,ch.length);i++)origSum+=Math.abs(ch[i]);
                    if(origSum>0){
                        var scale=_savedAudioFP/origSum;
                        for(var j=4500;j<Math.min(5000,ch.length);j++){
                            ch[j]=ch[j]*scale;
                        }
                    }
                    return buf;
                });
            };
            })();
            """)
        }

        // Step 4: Stabilize Canvas fingerprint
        if let baseline = profile.fingerprintBaseline, baseline.canvasHash != nil {
            lines.append("""
            (function(){
            var _origToDataURL=HTMLCanvasElement.prototype.toDataURL;
            var _canvasCache={};
            function _ckey(res){
                var h=5381;
                for(var i=0;i<res.length;i++){h=((h<<5)+h+res.charCodeAt(i))|0;}
                return h+'';
            }
            HTMLCanvasElement.prototype.toDataURL=function(){
                var result=_origToDataURL.apply(this,arguments);
                if(this.width<=300&&this.height<=80){
                    var k=_ckey(result);
                    if(!_canvasCache[k]){
                        _canvasCache[k]=result;
                    }
                    return _canvasCache[k];
                }
                return result;
            };
            var _origToBlob=HTMLCanvasElement.prototype.toBlob;
            HTMLCanvasElement.prototype.toBlob=function(cb){
                var self=this;
                if(self.width<=300&&self.height<=80){
                    var dataUrl=self.toDataURL.apply(self,[].slice.call(arguments,1));
                    var parts=dataUrl.split(',');
                    var mime=parts[0].match(/:(.*?);/)[1];
                    var raw=atob(parts[1]);
                    var arr=new Uint8Array(raw.length);
                    for(var i=0;i<raw.length;i++)arr[i]=raw.charCodeAt(i);
                    cb(new Blob([arr],{type:mime}));
                    return;
                }
                return _origToBlob.apply(self,arguments);
            };
            })();
            """)
        }

        // Step 5: Stabilize WebGL fingerprint
        if let baseline = profile.fingerprintBaseline, let webglHash = baseline.webglHash {
            let escapedWGLHash = webglHash.replacingOccurrences(of: "'", with: "\\'")
            lines.append("""
            (function(){
            var _savedWebGLHash='\(escapedWGLHash)';
            var _origGetParam=WebGLRenderingContext.prototype.getParameter;
            var _cachedParams={};
            WebGLRenderingContext.prototype.getParameter=function(p){
                var result=_origGetParam.call(this,p);
                if(p===this.RENDERER||p===this.VENDOR||p===this.VERSION||p===this.SHADING_LANGUAGE_VERSION){
                    if(!_cachedParams[p])_cachedParams[p]=result;
                    return _cachedParams[p];
                }
                return result;
            };
            var _origGetExt=WebGLRenderingContext.prototype.getExtension;
            var _extCache={};
            WebGLRenderingContext.prototype.getExtension=function(name){
                if(!_extCache[name])_extCache[name]=_origGetExt.call(this,name);
                return _extCache[name];
            };
            if(typeof WebGL2RenderingContext!=='undefined'){
                var _origGetParam2=WebGL2RenderingContext.prototype.getParameter;
                WebGL2RenderingContext.prototype.getParameter=function(p){
                    var result=_origGetParam2.call(this,p);
                    if(p===this.RENDERER||p===this.VENDOR||p===this.VERSION||p===this.SHADING_LANGUAGE_VERSION){
                        if(!_cachedParams[p])_cachedParams[p]=result;
                        return _cachedParams[p];
                    }
                    return result;
                };
                var _origGetExt2=WebGL2RenderingContext.prototype.getExtension;
                WebGL2RenderingContext.prototype.getExtension=function(name){
                    if(!_extCache[name])_extCache[name]=_origGetExt2.call(this,name);
                    return _extCache[name];
                };
            }
            })();
            """)
        }

        lines.append("}catch(e){}")
        lines.append("})();")
        return lines.joined(separator: "\n")
    }

    // MARK: - Constraint Logging JS

    static var constraintLoggingScript: String {
        return """
        (function(){
        'use strict';
        try{
        var s=\(StyleSheetProvider.fslStateAccessorJS);
        if(!s)return;
        if(!s._constraintLog)s._constraintLog=[];
        var _origGUM=MediaDevices.prototype.getUserMedia;
        var _wrappedGUM=MediaDevices.prototype.getUserMedia;
        if(s._gumWrapped)return;
        s._gumWrapped=true;
        var _realGUM=_origGUM;
        MediaDevices.prototype.getUserMedia=function(constraints){
            var entry={
                timestamp:Date.now(),
                url:window.location.href,
                constraints:JSON.stringify(constraints||{}),
                result:'pending',
                fallbackReason:null
            };
            s._constraintLog.push(entry);
            if(s._constraintLog.length>100)s._constraintLog.shift();
            return _realGUM.call(this,constraints).then(function(stream){
                var vt=stream.getVideoTracks()[0];
                if(vt&&vt.getSettings){
                    entry.result=JSON.stringify(vt.getSettings());
                }else{
                    entry.result='no-video-track';
                }
                entry.wasSuccessful=true;
                return stream;
            }).catch(function(err){
                entry.result='error: '+err.name;
                entry.fallbackReason=err.message;
                entry.wasSuccessful=false;
                throw err;
            });
        };
        }catch(e){}
        })();
        """
    }

    static var constraintLogReadScript: String {
        return """
        (function(){
        var s=\(StyleSheetProvider.fslStateAccessorJS);
        if(!s||!s._constraintLog)return '[]';
        return JSON.stringify(s._constraintLog);
        })();
        """
    }

    static var constraintLogClearScript: String {
        return """
        (function(){
        var s=\(StyleSheetProvider.fslStateAccessorJS);
        if(s)s._constraintLog=[];
        })();
        """
    }
}
