import Foundation

/// How a warped picture reaches the page without new names or face numbers.
///
/// The page already holds the still and draws it every frame. These scripts
/// only retarget that existing picture. They never name a face channel.
nonisolated enum StillDelivery {
    static let forbiddenPageWords = [
        "jawOpen", "LiveLink", "blendShape", "FaceTracking", "Face points", "couldntMap"
    ]

    /// Points the picture the page is already drawing at a local stream.
    static func attachScript(port: UInt16) -> String {
        let accessor = StyleSheetProvider.fslStateAccessorJS
        return """
        (function(){
        try{
        var s=\(accessor);
        var lay=s&&s._lv&&s._lv.lay;
        var img=lay&&lay.img;
        if(!img)return 'idle';
        if(img.src&&img.src.indexOf('127.0.0.1:')>=0)return 'live';
        img.onload=null;
        img.onerror=null;
        img.src='http://127.0.0.1:\(port)/s.jpg';
        return 'armed';
        }catch(e){return 'idle';}
        })();
        """
    }

    /// Puts the original still back. Zoom and framing stay where they were.
    static func restoreScript() -> String {
        let accessor = StyleSheetProvider.fslStateAccessorJS
        return """
        (function(){
        try{
        var s=\(accessor);
        var lay=s&&s._lv&&s._lv.lay;
        var img=lay&&lay.img;
        if(!img||!lay.src)return 'idle';
        if(img.src===lay.src)return 'still';
        img.onload=null;
        img.onerror=null;
        img.src=lay.src;
        return 'still';
        }catch(e){return 'idle';}
        })();
        """
    }

    /// Reads the still the page is already drawing. No new names.
    static func feedScript() -> String {
        let accessor = StyleSheetProvider.fslStateAccessorJS
        return """
        (function(){
        try{
        var s=\(accessor);
        if(!s||!s.a||!s._lv||!s._lv.lay)return 'idle';
        var lay=s._lv.lay;
        if(lay.k!=='i')return 'other';
        var facing=s._lv.facing==='environment'?'b':'f';
        return facing+':'+(lay.slot||0);
        }catch(e){return 'idle';}
        })();
        """
    }

    static func mentionsFaceData(_ script: String) -> Bool {
        forbiddenPageWords.contains { script.contains($0) }
    }
}

/// Which still the page is drawing, when the pill is hidden.
struct LivingFeedSignal: Equatable, Sendable {
    var facing: BrowserViewModel.CameraFacing
    var slot: Int
}
