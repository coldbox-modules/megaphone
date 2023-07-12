component extends="megaphone.models.BaseNotification" {

    public array function via( notifiable ) {
        return [ "doesntExist" ];
    }

}
