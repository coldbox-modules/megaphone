component extends="tests.resources.QueueNotification" {

    public array function via( required any notifiable ) {
        return [ "push" ];
    }
    public struct function toWebPush( required any notifiable, required any delivery ) {
        return { "title": "Queued push", "tag": arguments.delivery.getId() };
    }

}
