/** Internal durable publication job; never used as the application summary. */
component extends="megaphone.models.BaseNotification" {

    public array function via( required any notifiable ) {
        return [ "digestBatch" ];
    }

}
