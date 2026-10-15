/** cbq carries delivery references; Megaphone owns transport attempts and outcomes. */
component singleton implements="megaphone.models.Interfaces.INotificationQueue" {

    property name="settings" inject="box:moduleSettings:megaphone";
    property name="wirebox" inject="wirebox";
    property name="moduleService" inject="box:moduleService";

    /**
     * Enqueues a delivery-ID job on the selected registered cbq connection and queue.
     */
    public void function enqueue(
        required megaphone.models.Delivery.NotificationDelivery delivery,
        string connection,
        string queue
    ) {
        if ( !listFind( "queued,retryable,processing", arguments.delivery.getState() ) ) {
            return;
        }
        if ( !variables.moduleService.isModuleRegistered( "cbq" ) ) {
            throw(
                type = "Megaphone.Queue.MissingCBQ",
                message = "Install and configure cbq to queue notifications with Megaphone's cbq adapter."
            );
        }
        variables.moduleService.activateModule( "cbq" );
        if ( !variables.moduleService.isModuleActive( "cbq" ) ) {
            throw(
                type = "Megaphone.Queue.MissingCBQ",
                message = "The cbq module must be active to queue notifications with Megaphone's cbq adapter."
            );
        }
        var availableDate = arguments.delivery.getAvailableDate();
        if ( arguments.delivery.getState() == "processing" ) {
            availableDate = arguments.delivery.getLeaseUntil();
        }
        var job = variables.wirebox
            .getInstance( "NotificationDeliveryJob@megaphone" )
            .setProperties( { "deliveryId": arguments.delivery.getId() } )
            .setMaxAttempts( 1 )
            .setDelay( max( 0, dateDiff( "s", now(), availableDate ) ) );
        if ( !isNull( arguments.queue ) ) {
            job.onQueue( arguments.queue );
        } else if ( len( variables.settings.queue.defaultQueue ) ) {
            job.onQueue( variables.settings.queue.defaultQueue );
        }
        if ( !isNull( arguments.connection ) ) {
            job.onConnection( arguments.connection );
        } else if ( len( variables.settings.queue.defaultConnection ) ) {
            job.onConnection( variables.settings.queue.defaultConnection );
        }
        job.dispatch();
    }

    /** Bulk admission is optional; delayed references retain scalar scheduling semantics. */
    public void function enqueueMany( required array deliveries, string connection, string queue ) {
        var jobs = [];
        var activated = false;
        for ( var delivery in arguments.deliveries ) {
            if ( !listFind( "queued,retryable,processing", delivery.getState() ) ) {
                continue;
            }
            if ( !activated ) {
                if ( !variables.moduleService.isModuleRegistered( "cbq" ) ) {
                    throw(
                        type = "Megaphone.Queue.MissingCBQ",
                        message = "Install and configure cbq to queue notifications with Megaphone's cbq adapter."
                    );
                }
                variables.moduleService.activateModule( "cbq" );
                if ( !variables.moduleService.isModuleActive( "cbq" ) ) {
                    throw(
                        type = "Megaphone.Queue.MissingCBQ",
                        message = "The cbq module must be active to queue notifications with Megaphone's cbq adapter."
                    );
                }
                activated = true;
            }
            var availableDate = delivery.getState() == "processing" ? delivery.getLeaseUntil() : delivery.getAvailableDate();
            if ( dateDiff( "s", now(), availableDate ) > 0 ) {
                var scalar = { "delivery": delivery };
                for ( var key in [ "connection", "queue" ] ) {
                    if ( !isNull( arguments[ key ] ) ) {
                        scalar[ key ] = arguments[ key ];
                    }
                }
                enqueue( argumentCollection = scalar );
                continue;
            }
            var job = variables.wirebox
                .getInstance( "NotificationDeliveryJob@megaphone" )
                .setProperties( { "deliveryId": delivery.getId() } )
                .setMaxAttempts( 1 )
                .setDelay( 0 );
            if ( !isNull( arguments.connection ) ) {
                job.onConnection( arguments.connection );
            } else if ( len( variables.settings.queue.defaultConnection ) ) {
                job.onConnection( variables.settings.queue.defaultConnection );
            }
            if ( !isNull( arguments.queue ) ) {
                job.onQueue( arguments.queue );
            } else if ( len( variables.settings.queue.defaultQueue ) ) {
                job.onQueue( variables.settings.queue.defaultQueue );
            }
            jobs.append( job );
        }
        if ( jobs.isEmpty() ) {
            return;
        }
        var bulk = { "jobs": jobs, "batchSize": 100 };
        if ( !isNull( arguments.connection ) ) {
            bulk.connectionName = arguments.connection;
        } else if ( len( variables.settings.queue.defaultConnection ) ) {
            bulk.connectionName = variables.settings.queue.defaultConnection;
        }
        if ( !isNull( arguments.queue ) ) {
            bulk.queueName = arguments.queue;
        } else if ( len( variables.settings.queue.defaultQueue ) ) {
            bulk.queueName = variables.settings.queue.defaultQueue;
        }
        variables.wirebox.getInstance( "Dispatcher@cbq" ).bulkDispatch( argumentCollection = bulk );
    }

}
