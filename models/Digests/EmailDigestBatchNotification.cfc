/** Reconstructible batch reference. Content is rendered by the named digest at dispatch. */
component extends="megaphone.models.BaseNotification" {

    /**
     * Routes a stored batch reference to the internal digest mail Provider.
     * @returns array
     */
    public array function via( required any notifiable ) {
        return [ "emailDigestBatch" ];
    }

}
