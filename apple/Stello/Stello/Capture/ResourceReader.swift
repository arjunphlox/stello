import Foundation

/// The merge a fresh resource read goes through on Enrich. The page readers themselves live on
/// the Worker (`src/lib/readers/resource.js`), the one copy shared with web saves.
nonisolated enum ResourceReader {

    /// A refetch that reads less (bot wall, login interstitial) never erases what capture read.
    static func merge(fresh: ResourceMeta, previous: ResourceMeta?) -> ResourceMeta {
        guard let previous else { return fresh }
        var meta = fresh
        if meta.subtype == nil { meta.subtype = previous.subtype }
        if meta.worksWith.isEmpty { meta.worksWith = previous.worksWith }
        if meta.name == nil { meta.name = previous.name }
        if meta.maker == nil { meta.maker = previous.maker }
        if meta.pricing == nil { meta.pricing = previous.pricing }
        if meta.price == nil {
            meta.price = previous.price
            meta.currency = previous.currency
        }
        if meta.users == nil { meta.users = previous.users }
        if meta.likes == nil { meta.likes = previous.likes }
        if meta.canonicalURL == nil { meta.canonicalURL = previous.canonicalURL }
        return meta
    }
}
