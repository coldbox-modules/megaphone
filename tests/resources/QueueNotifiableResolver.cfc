component singleton {

    variables.owners = {};
    public any function register( required any notifiable ) {
        variables.owners[ arguments.notifiable.getNotifiableType() & ":" & arguments.notifiable.getNotifiableId() ] = arguments.notifiable;
        return this;
    }
    public any function resolve( required string type, required string id ) {
        return variables.owners[ arguments.type & ":" & arguments.id ];
    }

}
