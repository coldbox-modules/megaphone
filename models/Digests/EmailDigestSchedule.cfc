/** Adapts digest configuration to native ColdBox scheduled tasks. */
component {

    /**
     * Normalizes persistable shortcut strings and native frequency method arguments.
     * @returns struct
     */
    public struct function normalize( required any schedule ) {
        if (
            isObject( arguments.schedule ) && isInstanceOf(
                arguments.schedule,
                "coldbox.system.async.tasks.ScheduledTask"
            )
        ) {
            if ( arguments.schedule.getScheduled() ) {
                throw(
                    type = "Megaphone.Digests.InvalidSchedule",
                    message = "Use an unstarted scheduled task template."
                );
            }
            for (
                var name in [
                    "whenClosure",
                    "beforeTask",
                    "afterTask",
                    "onTaskFailure",
                    "onTaskSuccess"
                ]
            ) {
                if ( isCustomFunction( invoke( arguments.schedule, "get" & name ) ) ) {
                    throw(
                        type = "Megaphone.Digests.InvalidSchedule",
                        message = "Executable callbacks belong in the named definition so subscriptions can be restored after restart."
                    );
                }
            }
            var state = {};
            for (
                var name in listToArray( "period,spacedDelay,timeUnit,noOverlaps,dayOfTheMonth,dayOfTheWeek,weekends,weekdays,firstBusinessDay,lastBusinessDay,taskTime,startTime,endTime,annually,disabled" )
            ) {
                state[ name ] = invoke( arguments.schedule, "get" & name );
            }
            for ( var name in [ "startOnDateTime", "endOnDateTime" ] ) {
                var value = invoke( arguments.schedule, "get" & name );
                state[ name ] = len( value ) ? value.toString() : "";
            }
            return { "nativeTask": state, "nextRun": arguments.schedule.getStats().nextRun };
        }
        if ( isStruct( arguments.schedule ) && structKeyExists( arguments.schedule, "nativeTask" ) ) {
            return arguments.schedule;
        }
        if ( isSimpleValue( arguments.schedule ) ) {
            var parts = listToArray( trim( arguments.schedule ), " " );
            var frequencyArguments = [];
            for ( var i = 2; i <= parts.len(); i++ ) {
                frequencyArguments.append( parts[ i ] );
            }
            return { "cadence": parts[ 1 ], "arguments": frequencyArguments };
        }
        if ( isStruct( arguments.schedule ) && len( arguments.schedule.cadence ?: "" ) ) {
            return { "cadence": arguments.schedule.cadence, "arguments": arguments.schedule.arguments ?: [] };
        }
        throw(
            type = "Megaphone.Digests.InvalidSchedule",
            message = "Use a ColdBox frequency shortcut or method/arguments, or configure a named digest with a task or closure."
        );
    }

    /**
     * Configures the module-owned task; its callable always belongs to Megaphone.
     * @returns any
     */
    public any function configureTask( required any task, required any schedule ) {
        if ( isCustomFunction( arguments.schedule ) ) {
            arguments.schedule( arguments.task );
        } else if ( isStruct( arguments.schedule ) && structKeyExists( arguments.schedule, "nativeTask" ) ) {
            for ( var name in arguments.schedule.nativeTask ) {
                var value = arguments.schedule.nativeTask[ name ];
                if ( listFind( "startOnDateTime,endOnDateTime", name ) ) {
                    if ( len( value ) ) {
                        invoke(
                            arguments.task,
                            name == "startOnDateTime" ? "startOn" : "endOn",
                            [ listFirst( value, "T" ), listLast( value, "T" ) ]
                        );
                    }
                } else {
                    invoke( arguments.task, "set" & name, [ value ] );
                }
            }
            setBoundary( arguments.task, arguments.schedule.nextRun );
        } else if (
            isObject( arguments.schedule ) && isInstanceOf(
                arguments.schedule,
                "coldbox.system.async.tasks.ScheduledTask"
            )
        ) {
            if ( arguments.schedule.getScheduled() ) {
                throw(
                    type = "Megaphone.Digests.InvalidSchedule",
                    message = "Supply an unstarted task template, or use a configuration closure."
                );
            }
            for (
                var name in listToArray( "period,spacedDelay,timeUnit,delay,delayTimeUnit,noOverlaps,dayOfTheMonth,dayOfTheWeek,weekends,weekdays,firstBusinessDay,lastBusinessDay,taskTime,startOnDateTime,endOnDateTime,startTime,endTime,annually,disabled,whenClosure,beforeTask,afterTask,onTaskFailure,onTaskSuccess,timezone" )
            ) {
                var value = invoke( arguments.schedule, "get" & name );
                if ( name == "timezone" ) {
                    value = value.getId();
                }
                if ( listFind( "startOnDateTime,endOnDateTime", name ) && !len( value ) ) {
                    continue;
                }
                invoke( arguments.task, "set" & name, [ value ] );
            }
            if (
                isInstanceOf( arguments.schedule, "coldbox.system.web.tasks.ColdBoxScheduledTask" ) && isInstanceOf(
                    arguments.task,
                    "coldbox.system.web.tasks.ColdBoxScheduledTask"
                )
            ) {
                for (
                    var name in [
                        "environments",
                        "serverFixation",
                        "cacheName",
                        "serverLockTimeout"
                    ]
                ) {
                    invoke( arguments.task, "set" & name, [ invoke( arguments.schedule, "get" & name ) ] );
                }
            }
            setBoundary( arguments.task, arguments.schedule.getStats().nextRun );
        } else {
            var timing = normalize( arguments.schedule );
            if (
                !reFindNoCase(
                    "^(every|spacedDelay|daily$|hourly$|weekly$|monthly$|yearly$|annually$|on(Mondays|Tuesdays|Wednesdays|Thursdays|Fridays|Saturdays|Sundays|Weekdays|Weekends|FirstBusinessDayOfTheMonth|LastBusinessDayOfTheMonth))",
                    timing.cadence
                ) || !isCustomFunction( arguments.task[ timing.cadence ] ?: "" )
            ) {
                throw(
                    type = "Megaphone.Digests.InvalidSchedule",
                    message = "cadence must name a ColdBox scheduled task frequency method."
                );
            }
            invoke( arguments.task, timing.cadence, timing.arguments );
        }
        if ( arguments.task.getScheduled() ) {
            throw(
                type = "Megaphone.Digests.InvalidSchedule",
                message = "Configure the task without starting it; Megaphone starts it with its own callable."
            );
        }
        return arguments.task;
    }

    /** Restores a template boundary in its native unit, advancing an expired recurring template. */
    private void function setBoundary( required any task, required string nextRun ) {
        if ( !len( arguments.nextRun ) ) {
            return;
        }
        var target = createObject( "java", "java.time.LocalDateTime" ).parse( arguments.nextRun );
        var current = arguments.task.getJavaNow();
        var unit = new coldbox.system.async.time.TimeUnit().get( arguments.task.getTimeUnit() );
        var interval = arguments.task.getSpacedDelay() > 0 ? arguments.task.getSpacedDelay() : arguments.task.getPeriod();
        var periodNanos = unit.toNanos( javacast( "long", interval ) );
        var duration = createObject( "java", "java.time.Duration" );
        if ( target.compareTo( current ) <= 0 && periodNanos > 0 ) {
            var steps = floor( duration.between( target, current ).toNanos() / periodNanos ) + 1;
            target = target.plusNanos( javacast( "long", steps * periodNanos ) );
        }
        var amount = max( 0, duration.between( current, target ).toNanos() / unit.toNanos( javacast( "long", 1 ) ) );
        arguments.task.delay(
            amount,
            arguments.task.getTimeUnit(),
            true,
            false
        );
        arguments.task.getStats().nextRun = target.toString();
    }

    /**
     * Uses the same timezone identifiers and validation as ColdBox.
     * @returns string
     */
    public string function timezone( string name = "UTC" ) {
        return createObject( "java", "java.time.ZoneId" ).of( arguments.name ).getId();
    }

    /**
     * Converts a saved occurrence date to UTC epoch milliseconds.
     * @returns numeric
     */
    public numeric function epoch( date clock = now() ) {
        return parseDateTime( arguments.clock ).getTime();
    }

    /**
     * Returns the task's scheduled boundary, rather than its possibly delayed execution time.
     * @returns numeric
     */
    public numeric function cutoff( required any task ) {
        var nextRun = arguments.task.getStats().nextRun;
        if ( !len( nextRun ) ) {
            return epoch();
        }
        return createObject( "java", "java.time.LocalDateTime" )
            .parse( nextRun )
            .withNano( javacast( "int", 0 ) )
            .atZone( arguments.task.getTimezone() )
            .toInstant()
            .toEpochMilli();
    }

}
