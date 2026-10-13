/** Keeps cbq activation available to synchronous users without choosing application providers. */
component extends="cbq.models.BaseConfig" {

    public void function configure() {
        // Durable queue users register their connections and workers through cbq's application config.
    }

}
