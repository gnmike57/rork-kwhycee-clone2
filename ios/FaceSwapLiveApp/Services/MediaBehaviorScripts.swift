import Foundation

/// Scripts for the device-matched media layer.
///
/// These only write into the `fsl` state object the patch script already
/// created. With `MediaBehaviorSettings.allOff` every value written here is
/// `false` or `null`, which is exactly what the patch script installed — so the
/// page behaves as it did before this feature set existed.
extension StyleSheetProvider {

    static func jsEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// A decimal literal for injected page code.
    ///
    /// `String(format:)` follows the user's region, so a comma-decimal device
    /// would write `0,5` into JavaScript — code the page cannot parse and every
    /// switch silently dies. Page code always gets the POSIX form.
    nonisolated static func jsNumber(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// Pushes every device-matched media switch into the page. No reload needed.
    static func cropJSArray(_ crop: StillCrop) -> String {
        "[\(jsNumber(crop.zoom, decimals: 4)),\(jsNumber(crop.panX, decimals: 4)),\(jsNumber(crop.panY, decimals: 4))]"
    }

    /// One still's framing as a map keyed by frame shape.
    ///
    /// Only shapes the user has actually framed are written, so an untouched
    /// slot arrives as `{}` — which the page reads as the plain cover-fit the
    /// single identity crop always meant.
    static func cropMapJS(_ crops: ShapeCrops) -> String {
        let entries = crops.framedShapes.map { shape in
            "\(shape.jsKey):\(cropJSArray(crops[shape]))"
        }
        return "{" + entries.joined(separator: ",") + "}"
    }

    static func behaviorApplyScript(
        settings: MediaBehaviorSettings,
        audit: DeviceAuditProfile,
        reportStatus: Bool,
        motionFrozen: Bool,
        identitySecret: String = "",
        frontCrop: ShapeCrops = .identity,
        frontCrop2: ShapeCrops = .identity,
        backCrop: ShapeCrops = .identity,
        backCrop2: ShapeCrops = .identity,
        frontVideoZoom: Double = 1,
        backVideoZoom: Double = 1
    ) -> String {
        let limits = audit.limits

        let auditListJS: String
        let auditMicsJS: String
        let auditMicJS: String
        if settings.useAuditProfile {
            auditListJS = "[" + audit.cameras
                .sorted { $0.order < $1.order }
                .map(cameraEntryJS)
                .joined(separator: ",") + "]"

            // Every input carries its own identity and borrows only the group of
            // the camera it sits with, which is what the readings measured.
            let mics = audit.microphones.sorted { $0.order < $1.order }.map { mic in
                // `h` is this input's own handle; `gh` is the camera whose GROUP
                // it shares. The page turns both into per-site values.
                "{h:'\(mic.deviceIdPrefix)',gh:'\(mic.groupWithCameraPrefix ?? mic.deviceIdPrefix)',"
                    + "deviceId:'\(mic.deviceId)',groupId:'\(mic.groupId(in: audit.cameras))',"
                    + "label:'\(jsEscaped(mic.label))',sampleRate:\(mic.sampleRate),"
                    + "sampleSize:\(mic.sampleSize),channelCount:\(mic.channelCount),"
                    + "echoCancellation:\(mic.echoCancellation),"
                    + "autoGainControl:\(mic.autoGainControl),"
                    + "noiseSuppression:\(mic.noiseSuppression),"
                    + "latency:\(jsNumber(mic.latency, decimals: 6))}"
            }
            auditMicsJS = "[" + mics.joined(separator: ",") + "]"
            auditMicJS = mics.first ?? "null"
        } else {
            auditListJS = "null"
            auditMicsJS = "null"
            auditMicJS = "null"
        }

        let limitsJS: String
        if settings.capabilityValidation {
            limitsJS = "{maxWidth:\(limits.maxWidth),maxHeight:\(limits.maxHeight),"
                + "minWidth:\(limits.minWidth),minHeight:\(limits.minHeight),"
                + "maxFrameRate:\(Int(limits.maxFrameRate)),minFrameRate:\(Int(limits.minFrameRate)),"
                + "name:'\(jsEscaped(limits.rejectionErrorName))',msg:'\(jsEscaped(limits.rejectionErrorMessage))',"
                + "typeName:'\(jsEscaped(AuditRefusal.typeErrorName))',"
                + "typeMsg:'\(jsEscaped(AuditRefusal.nonFiniteMessage))'}"
        } else {
            limitsJS = "null"
        }

        let strength = jsNumber(settings.motionStrength.multiplier, decimals: 3)

        var lines: [String] = [
            "(function(){",
            "try{",
            "var s=\(StyleSheetProvider.fslStateAccessorJS);",
            "if(!s)return;",
            "s.mo=\(settings.liveMotion);",
            "s.mok=\(strength);",
            "s.grain=\(settings.sensorGrain);",
            "s.jit=\(settings.frameTimingJitter);",
            "s.skin=\(settings.skinRealism);",
            "s.expo=\(settings.exposureBreathing);",
            "s.frz=\(motionFrozen);",
            "s.pr=\(settings.promptLiveRequests);",
            "s.prf=\(settings.promptFileRequests);",
            "s.prsec=\(Int(settings.promptHoldSeconds));",
            "s.crop=\(settings.liveStillCrop);",
            "s.onepass=\(settings.autoOffAfterOnePass);",
            "s.fc=\(cropMapJS(frontCrop));",
            "s.fc2=\(cropMapJS(frontCrop2));",
            "s.bc=\(cropMapJS(backCrop));",
            "s.bc2=\(cropMapJS(backCrop2));",
            "s.lzf=\(jsNumber(frontVideoZoom, decimals: 4));",
            "s.lzb=\(jsNumber(backVideoZoom, decimals: 4));",
            "s.cap=\(settings.capabilityValidation);",
            "s.caplim=\(limitsJS);",
            "s.auditList=\(auditListJS);",
            "s.auditMics=\(auditMicsJS);",
            "s.auditMic=\(auditMicJS);",
            // Left alone here on purpose. This script is prepared before the
            // app knows which site is loading, so baking a grant in would hand a
            // brand-new site the last site's state. `siteStateScript` sets it
            // per site once the page is really there.
            "s.idsec='\(jsEscaped(identitySecret))';",
            // Turns the handles above into this site's own identifiers. Done in
            // the page rather than handed in, so a page that asks at the very
            // first moment gets its own site's values and never the last one's.
            "if(s._siteIds)s._siteIds();",
            "s.rep=\(reportStatus);",
            "}catch(e){}",
            "})();"
        ]

        if settings.graphicsAlignment {
            lines.append(hardwareAlignmentJS(audit: audit))
        }

        return lines.joined(separator: "\n")
    }

    /// One camera, with everything the readings measured about it.
    ///
    /// The size ladder travels with the camera because real hardware answers from
    /// its own short list of modes rather than a smooth range.
    private static func cameraEntryJS(_ camera: AuditCamera) -> String {
        let modes = camera.modes
            .map { "[\($0.width),\($0.height)]" }
            .joined(separator: ",")
        let rates = camera.frameRateSteps
            .map { String(Int($0)) }
            .joined(separator: ",")
        let wb = camera.whiteBalanceModes
            .map { "'" + jsEscaped($0) + "'" }
            .joined(separator: ",")
        // `h` is the handle the readings recorded for this camera. It is never
        // reported as-is: the page mixes it with the site's own name so each site
        // gets its own identifiers, which is what a real phone does.
        return "{h:'\(camera.deviceIdPrefix)',"
            + "deviceId:'\(camera.deviceId)',groupId:'\(camera.groupId)',"
            + "label:'\(jsEscaped(camera.label))',facing:'\(jsEscaped(camera.facingMode))',"
            + "modes:[\(modes)],rates:[\(rates)],"
            + "def:[\(camera.defaultMode.width),\(camera.defaultMode.height)],"
            + "nat:[\(camera.nativeMaxMode.width),\(camera.nativeMaxMode.height)],"
            + "fps:\(Int(camera.grantedFrameRate)),openMs:\(Int(camera.nativeMaxOpenMs)),"
            + "minZoom:\(camera.minZoom),maxZoom:\(camera.maxZoom),"
            + "wb:[\(wb)],torch:\(camera.hasTorch)}"
    }

    /// Graphics, screen and codec answers taken straight from the audit sheet.
    private static func hardwareAlignmentJS(audit: DeviceAuditProfile) -> String {
        let web = audit.web
        let renderer = jsEscaped(web.glRenderer)
        let vendor = jsEscaped(web.glVendor)
        let unmasked = jsEscaped(web.glUnmaskedVendor)
        let shading = jsEscaped(web.glShadingLanguageVersion)
        let types = web.supportedRecordingTypes
            .map { "'" + jsEscaped($0.lowercased()) + "'" }
            .joined(separator: ",")
        let gpu = web.graphics
        let extensions = gpu.extensions
            .map { "'" + jsEscaped($0) + "'" }
            .joined(separator: ",")
        let lineRange = gpu.aliasedLineWidthRange.map(String.init).joined(separator: ",")
        let pointRange = gpu.aliasedPointSizeRange.map(String.init).joined(separator: ",")

        let memoryJS: String
        if let memory = web.deviceMemory {
            memoryJS = "lock(navigator,'deviceMemory',\(memory));"
        } else {
            // The audited device does not expose deviceMemory at all, so the
            // name is removed rather than answered with a blank.
            memoryJS = "try{var NP=Object.getPrototypeOf(navigator);"
                + "if(NP&&Object.getOwnPropertyDescriptor(NP,'deviceMemory'))delete NP.deviceMemory;"
                + "if(Object.getOwnPropertyDescriptor(navigator,'deviceMemory'))delete navigator.deviceMemory;}catch(e){}"
        }

        var body: [String] = []
        body.append("(function(){")
        body.append("'use strict';")
        body.append("try{")
        body.append("var S=\(StyleSheetProvider.fslStateAccessorJS);")
        body.append("var NAT=(S&&S._asNative)?S._asNative:function(f){return f;};")
        body.append("var FIRST=(S&&S._firstTouch)?S._firstTouch:function(){return true;};")
        // A real readonly attribute lives on the prototype with its getter named
        // "get <name>", not as an own property of the instance. Defining it where
        // the built-in one lives means a page looking for an own property on
        // navigator or screen finds nothing, exactly as on a real phone.
        body.append("function lock(o,n,v){")
        body.append("try{")
        body.append("var proto=Object.getPrototypeOf(o);")
        body.append("var target=(proto&&Object.getOwnPropertyDescriptor(proto,n))?proto:o;")
        body.append("var g=NAT(function(){return v;},'get '+n);")
        body.append("Object.defineProperty(target,n,{get:g,set:undefined,configurable:true,enumerable:true});")
        body.append("if(target!==o){try{delete o[n];}catch(e2){}}")
        body.append("}catch(e){}")
        body.append("}")
        body.append("lock(navigator,'hardwareConcurrency',\(web.hardwareConcurrency));")
        body.append("lock(navigator,'maxTouchPoints',\(web.maxTouchPoints));")
        body.append(memoryJS)
        body.append("lock(screen,'width',\(web.screenWidth));")
        body.append("lock(screen,'height',\(web.screenHeight));")
        body.append("lock(screen,'availWidth',\(web.screenWidth));")
        body.append("lock(screen,'availHeight',\(web.screenHeight));")
        body.append("lock(screen,'colorDepth',\(web.colorDepth));")
        body.append("lock(screen,'pixelDepth',\(web.colorDepth));")
        body.append("var RENDERER='\(renderer)';")
        body.append("var VENDOR='\(vendor)';")
        body.append("var UNMASKED='\(unmasked)';")
        body.append("var SHADING='\(shading)';")
        body.append("var GLVER='\(jsEscaped(gpu.glVersion))';")
        body.append("var GLEXT=[\(extensions)];")
        // The measured graphics answer sheet. A page that cross-checks these
        // against the renderer name finds them consistent with each other.
        body.append("var GLNUM={")
        body.append("MAX_TEXTURE_SIZE:\(gpu.maxTextureSize),")
        body.append("MAX_CUBE_MAP_TEXTURE_SIZE:\(gpu.maxCubeMapSize),")
        body.append("MAX_RENDERBUFFER_SIZE:\(gpu.maxRenderbufferSize),")
        body.append("MAX_VERTEX_ATTRIBS:\(gpu.maxVertexAttributes),")
        body.append("MAX_VERTEX_UNIFORM_VECTORS:\(gpu.maxVertexUniformVectors),")
        body.append("MAX_FRAGMENT_UNIFORM_VECTORS:\(gpu.maxFragmentUniformVectors),")
        body.append("MAX_VARYING_VECTORS:\(gpu.maxVaryingVectors),")
        body.append("MAX_TEXTURE_IMAGE_UNITS:\(gpu.maxTextureImageUnits),")
        body.append("MAX_COMBINED_TEXTURE_IMAGE_UNITS:\(gpu.maxCombinedTextureUnits),")
        body.append("RED_BITS:\(gpu.colorBits),GREEN_BITS:\(gpu.colorBits),")
        body.append("BLUE_BITS:\(gpu.colorBits),ALPHA_BITS:\(gpu.colorBits),")
        body.append("DEPTH_BITS:\(gpu.depthBits),STENCIL_BITS:\(gpu.stencilBits)};")
        body.append("var GLVP=[\(gpu.maxViewportWidth),\(gpu.maxViewportHeight)];")
        body.append("var GLLINE=[\(lineRange)];")
        body.append("var GLPOINT=[\(pointRange)];")
        body.append("var GLANISO=\(gpu.maxAnisotropy);")
        // Compares against the context's own constant, and only when that
        // constant genuinely exists — the varying-vector name is WebGL 1 only.
        body.append("function eqp(g,n,p){var c=g[n];return typeof c==='number'&&p===c;}")
        body.append("function patchGL(proto){")
        // Tracked off to the side. A marker property here would sit on the
        // graphics prototype for any page to read.
        body.append("if(!proto||!FIRST(proto))return;")
        body.append("var orig=proto.getParameter;")
        body.append("proto.getParameter=NAT(function getParameter(p){")
        body.append("try{")
        body.append("var dbg=this.getExtension?this.getExtension('WEBGL_debug_renderer_info'):null;")
        body.append("if(dbg){")
        body.append("if(p===dbg.UNMASKED_RENDERER_WEBGL)return RENDERER;")
        body.append("if(p===dbg.UNMASKED_VENDOR_WEBGL)return UNMASKED;")
        body.append("}")
        body.append("if(p===this.RENDERER)return RENDERER;")
        body.append("if(p===this.VENDOR)return VENDOR;")
        body.append("if(p===this.SHADING_LANGUAGE_VERSION)return SHADING;")
        body.append("if(p===this.VERSION)return GLVER;")
        body.append("if(eqp(this,'MAX_VIEWPORT_DIMS',p))return new Int32Array(GLVP);")
        body.append("if(eqp(this,'ALIASED_LINE_WIDTH_RANGE',p))return new Float32Array(GLLINE);")
        body.append("if(eqp(this,'ALIASED_POINT_SIZE_RANGE',p))return new Float32Array(GLPOINT);")
        body.append("for(var k in GLNUM){if(eqp(this,k,p))return GLNUM[k];}")
        body.append("var an=this.getExtension?(this.getExtension('EXT_texture_filter_anisotropic')||this.getExtension('WEBKIT_EXT_texture_filter_anisotropic')):null;")
        body.append("if(an&&p===an.MAX_TEXTURE_MAX_ANISOTROPY_EXT)return GLANISO;")
        body.append("}catch(e){}")
        body.append("return orig.call(this,p);")
        body.append("},'getParameter');")
        body.append("var origExt=proto.getSupportedExtensions;")
        body.append("if(origExt){")
        body.append("proto.getSupportedExtensions=NAT(function getSupportedExtensions(){")
        body.append("try{return GLEXT.slice();}catch(e){return origExt.call(this);}")
        body.append("},'getSupportedExtensions');")
        body.append("}")
        body.append("}")
        body.append("if(typeof WebGLRenderingContext!=='undefined')patchGL(WebGLRenderingContext.prototype);")
        body.append("if(typeof WebGL2RenderingContext!=='undefined')patchGL(WebGL2RenderingContext.prototype);")
        // Real Safari answers per container and codec, not per exact string:
        // an avc1 profile level it never named still counts, a second codec in
        // the list is fine, and quoting or spacing changes nothing.
        body.append("var TYPES=[\(types)];")
        body.append("function normType(t){")
        body.append("var q=String(t).toLowerCase().split(' ').join('');")
        body.append("var semi=q.indexOf(';');")
        body.append("var base=semi>=0?q.slice(0,semi):q;")
        body.append("var codecs=[];")
        body.append("if(semi>=0){")
        body.append("var rest=q.slice(semi+1).replace(/\"/g,'');")
        body.append("if(rest.indexOf('codecs=')===0)rest=rest.slice(7);")
        body.append("if(rest){codecs=rest.split(',');}")
        body.append("}")
        body.append("return{base:base,codecs:codecs};")
        body.append("}")
        body.append("var BASES=Object.create(null);")
        body.append("var CODECS=Object.create(null);")
        body.append("for(var ti=0;ti<TYPES.length;ti++){")
        body.append("var e=normType(TYPES[ti]);")
        body.append("BASES[e.base]=true;")
        body.append("for(var tc=0;tc<e.codecs.length;tc++){CODECS[e.codecs[tc]]=true;}")
        body.append("}")
        body.append("if(typeof MediaRecorder!=='undefined'&&MediaRecorder.isTypeSupported&&FIRST(MediaRecorder)){")
        body.append("MediaRecorder.isTypeSupported=NAT(function isTypeSupported(t){")
        body.append("if(!t)return false;")
        body.append("var req=normType(t);")
        body.append("if(!BASES[req.base])return false;")
        body.append("if(!req.codecs.length)return true;")
        body.append("for(var i=0;i<req.codecs.length;i++){")
        body.append("var c=req.codecs[i];")
        body.append("if(CODECS[c])continue;")
        body.append("var ok=false;")
        body.append("var cfam=c.split('.')[0];")
        body.append("for(var k in CODECS){")
        body.append("if(k===c||k.indexOf(c)===0||c.indexOf(k)===0||k.split('.')[0]===cfam){ok=true;break;}")
        body.append("}")
        body.append("if(!ok)return false;")
        body.append("}")
        body.append("return true;")
        body.append("},'isTypeSupported');")
        body.append("}")
        body.append("}catch(e){}")
        body.append("})();")
        return body.joined(separator: "\n")
    }

    /// Asks a running feed to fade itself over to the next item in its queue.
    ///
    /// Returns `fade:<front>:<back>` when the page took the change on, `busy`
    /// when one is already running, and `none` when nothing is live — in which
    /// case the caller falls back to the plain queue step below.
    static var fadeNextScript: String {
        var lines: [String] = []
        lines.append("(function(){")
        lines.append("try{")
        lines.append("var s=\(StyleSheetProvider.fslStateAccessorJS);")
        lines.append("if(!s||!s._fadeNext)return 'none';")
        lines.append("return s._fadeNext(null)||'none';")
        lines.append("}catch(e){return 'none';}")
        lines.append("})();")
        return lines.joined(separator: "\n")
    }

    /// Clears what the live feed is holding and draws the current queue item in
    /// again, without renegotiating the site's own stream.
    ///
    /// Answers `live` when a running feed was re-drawn, `cleared` when only a
    /// stuck handover was dropped, and `idle` when nothing is live — in which
    /// case the caller re-sends the media state instead.
    static var forceReinjectScript: String {
        var lines: [String] = []
        lines.append("(function(){")
        lines.append("try{")
        lines.append("var s=\(StyleSheetProvider.fslStateAccessorJS);")
        lines.append("if(!s||!s._forceReinject)return 'idle';")
        lines.append("return s._forceReinject()||'idle';")
        lines.append("}catch(e){return 'idle';}")
        lines.append("})();")
        return lines.joined(separator: "\n")
    }

    /// Advances both camera queues in the page, mirroring the pill's Next button.
    static var advanceBothQueuesScript: String {
        var lines: [String] = []
        lines.append("(function(){")
        lines.append("var s=\(StyleSheetProvider.fslStateAccessorJS);")
        lines.append("if(!s)return '0:0';")
        lines.append("if(s.onepass){")
        lines.append("if(s.fseq&&s.fseq.length>1&&(s.fi||0)+1<s.fseq.length)s.fi=(s.fi||0)+1;")
        lines.append("if(s.bseq&&s.bseq.length>1&&(s.bi||0)+1<s.bseq.length)s.bi=(s.bi||0)+1;")
        lines.append("}else{")
        lines.append("if(s.fseq&&s.fseq.length>1)s.fi=((s.fi||0)+1)%s.fseq.length;")
        lines.append("if(s.bseq&&s.bseq.length>1)s.bi=((s.bi||0)+1)%s.bseq.length;")
        lines.append("}")
        lines.append("return (s.fi||0)+':'+(s.bi||0);")
        lines.append("})();")
        return lines.joined(separator: "\n")
    }

    /// Per-site state, applied once the page being loaded is really known.
    ///
    /// Kept out of the document-start script deliberately: that script is built
    /// before the app knows where it is going, and it is shared by every site.
    /// The granted list itself is never handed to a page — only this one site's
    /// answer about itself — so a page cannot learn anywhere else the user has
    /// been.
    ///
    /// Both grants are written absolutely, so revoking one in the app is
    /// reflected the next time this runs — a previously granted page drops back
    /// to `prompt` instead of holding the old answer forever.
    static func siteStateScript(cameraGranted: Bool, microphoneGranted: Bool) -> String {
        var lines: [String] = []
        lines.append("(function(){")
        lines.append("try{")
        lines.append("var s=\(StyleSheetProvider.fslStateAccessorJS);")
        lines.append("if(!s)return;")
        lines.append("s.gr=\(cameraGranted);")
        lines.append("s.grm=\(microphoneGranted);")
        // Identifiers are recomputed here too, so a page that arrives before the
        // first apply still sees its own site's values.
        lines.append("if(s._siteIds)s._siteIds();")
        lines.append("}catch(e){}")
        lines.append("})();")
        return lines.joined(separator: "\n")
    }

    /// Holds the live picture perfectly still, or lets it move again.
    ///
    /// Kept separate from the full apply so the pill's Freeze button is a single
    /// cheap write rather than a re-application of every switch.
    static func freezeScript(frozen: Bool) -> String {
        var lines: [String] = []
        lines.append("(function(){")
        lines.append("try{")
        lines.append("var s=\(StyleSheetProvider.fslStateAccessorJS);")
        lines.append("if(s)s.frz=\(frozen);")
        lines.append("}catch(e){}")
        lines.append("})();")
        return lines.joined(separator: "\n")
    }

    /// Pushes per-still framing without re-applying every switch.
    static func stillCropPushScript(
        enabled: Bool,
        front: ShapeCrops,
        front2: ShapeCrops,
        back: ShapeCrops,
        back2: ShapeCrops
    ) -> String {
        var lines: [String] = []
        lines.append("(function(){")
        lines.append("try{")
        lines.append("var s=\(StyleSheetProvider.fslStateAccessorJS);")
        lines.append("if(!s)return;")
        lines.append("s.crop=\(enabled);")
        lines.append("s.fc=\(cropMapJS(front));")
        lines.append("s.fc2=\(cropMapJS(front2));")
        lines.append("s.bc=\(cropMapJS(back));")
        lines.append("s.bc2=\(cropMapJS(back2));")
        lines.append("}catch(e){}")
        lines.append("})();")
        return lines.joined(separator: "\n")
    }

    /// Pushes a running clip's live zoom. One number per camera, read by the
    /// video draw loop on its very next frame — no rebuild, no reload.
    ///
    /// Stills carry their zoom in the framing maps instead, so this only ever
    /// moves a video.
    static func videoZoomPushScript(front: Double, back: Double) -> String {
        var lines: [String] = []
        lines.append("(function(){")
        lines.append("try{")
        lines.append("var s=\(StyleSheetProvider.fslStateAccessorJS);")
        lines.append("if(!s)return;")
        lines.append("s.lzf=\(jsNumber(front, decimals: 4));")
        lines.append("s.lzb=\(jsNumber(back, decimals: 4));")
        lines.append("}catch(e){}")
        lines.append("})();")
        return lines.joined(separator: "\n")
    }

    /// The exact frame the running feed is drawing into, as `w:h`, or `none`.
    ///
    /// Read straight off the live canvas rather than inferred, so the app zooms
    /// the very framing the page is using.
    static var liveFrameSizeScript: String {
        var lines: [String] = []
        lines.append("(function(){")
        lines.append("try{")
        lines.append("var s=\(StyleSheetProvider.fslStateAccessorJS);")
        lines.append("if(!s||!s._lv||!s._lv.cnv)return 'none';")
        lines.append("return s._lv.cnv.width+':'+s._lv.cnv.height;")
        lines.append("}catch(e){return 'none';}")
        lines.append("})();")
        return lines.joined(separator: "\n")
    }

    /// Moves one camera queue to a specific slot so the pill and Next agree.
    static func setQueueIndexScript(front: Int?, back: Int?) -> String {
        var lines: [String] = []
        lines.append("(function(){")
        lines.append("try{")
        lines.append("var s=\(StyleSheetProvider.fslStateAccessorJS);")
        lines.append("if(!s)return;")
        if let front {
            lines.append("s.fi=\(front);")
        }
        if let back {
            lines.append("s.bi=\(back);")
        }
        lines.append("}catch(e){}")
        lines.append("})();")
        return lines.joined(separator: "\n")
    }

    /// Hands a prompt decision back to the waiting page.
    static func resolvePromptScript(id: Int, decision: MediaRequestDecision) -> String {
        var lines: [String] = []
        lines.append("(function(){")
        lines.append("try{")
        lines.append("var s=\(StyleSheetProvider.fslStateAccessorJS);")
        lines.append("if(s&&s._resolvePrompt)s._resolvePrompt(\(id),\(decision.jsLiteral));")
        lines.append("}catch(e){}")
        lines.append("})();")
        return lines.joined(separator: "\n")
    }
}
