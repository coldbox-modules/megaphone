/**
 * Processes WireBox DSL's starting with "megaphone:"
 */
component {

    /**
     * Creates the Quick Service DSL Processor.
     *
     * @injector  The WireBox injector.
     *
     * @return    QuickServiceDSL
     */
    public MegaphoneDSL function init( required Injector injector ) {
        variables.injector = arguments.injector;
        return this;
    }

    /**
     * Creates a Quick BaseService from the dsl.
     * The portion after the colon is used as the entity mapping.
     *
     * @definition  The dsl struct definition.
     *
     * @return      BaseService or extending component.
     */
    public any function process( required struct definition ) {
        param variables.megaphone = variables.injector.getInstance( "NotificationService@megaphone" );
        return variables.megaphone.getChannel( listRest( arguments.definition.dsl, ":" ) );
    }

}
