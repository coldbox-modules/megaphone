/** Captures a collection intent; a guarded fallback must fail before collection writes. */
component {

    public boolean function supportsCollection() {
        return true;
    }
    public struct function getCollectionIntent( required any notifiable, required any notification ) {
        return { "name": "fixture-digest" };
    }

}
