component extends="megaphone.models.BaseNotification" {

    property name="state" inject="GenericDigestState@megaphone";

    function via( notifiable ) {
        return variables.state.getChannels();
    }

    function toSummary( notifiable ) {
        var data = {
            "keys": variables.items.map( ( item ) => item.itemKey ),
            "digestName": variables.digestName,
            "batchId": variables.batchId
        };
        variables.state.getFormatted().append( data );
        if ( !isNull( variables.state.getOnFormat() ) ) {
            variables.state.getOnFormat()();
        }
        return data;
    }

}
