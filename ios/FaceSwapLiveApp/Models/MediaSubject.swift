import Foundation

/// What a clip is *of*, which is the only thing needed to know which camera it
/// belongs to.
///
/// A face means the clip stands in for a selfie / liveness capture, which only
/// ever comes from the front camera. Anything without a face — a card, an ID, a
/// passport, a utility bill — is held in front of the back camera. There is no
/// third case, so a clip is only ever prepared for one camera.
nonisolated enum MediaSubject: String, Codable, Sendable, CaseIterable {
    case person
    case document

    var label: String {
        switch self {
        case .person: return "Person"
        case .document: return "Document"
        }
    }

    var cameraLabel: String {
        switch self {
        case .person: return "Front"
        case .document: return "Back"
        }
    }

    var systemImage: String {
        switch self {
        case .person: return "person.crop.square"
        case .document: return "doc.text.image"
        }
    }

    var opposite: MediaSubject {
        self == .person ? .document : .person
    }
}

/// Outcome of looking at a clip, kept with the clip so the reason stays visible
/// and the user can disagree with it.
nonisolated struct MediaSubjectDecision: Sendable {
    var subject: MediaSubject
    var reason: String
}
