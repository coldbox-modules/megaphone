component extends="megaphone.models.BaseNotification" accessors="true" {

    public array function via( required any notifiable ) {
        return variables.channelNames ?: [ "database" ];
    }
    public struct function getChannelPreferences( required any notifiable ) {
        var result = {};
        for ( var channelName in via( arguments.notifiable ) ) {
            result[ channelName ] = {
                "enabled": !structKeyExists( variables, "choices" ) || !structKeyExists(
                    variables.choices,
                    channelName
                ) || variables.choices[ channelName ]
            };
        }
        return result;
    }
    public struct function toDatabase( required any notifiable ) {
        return { "message": variables.message ?: "queued" };
    }

}
