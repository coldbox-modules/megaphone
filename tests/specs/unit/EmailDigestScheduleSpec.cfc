component extends="testbox.system.BaseSpec" {

    function run() {
        describe( "Native ColdBox digest schedules", () => {
            beforeEach( () => {
                variables.calendar = new megaphone.models.Digests.EmailDigestSchedule();
                variables.task = new coldbox.system.async.tasks.ScheduledTask( "digest", {} ).setTimezone( "America/Denver" );
            } );
            it( "uses the native weekly method and ISO weekday numbering", () => {
                variables.calendar.configureTask( variables.task, "everyWeekOn 1 09:00" );
                expect( variables.task.getDayOfTheWeek() ).toBe( 1 );
                expect( variables.task.getPeriod() ).toBe( 7 * 24 * 60 * 60 );
                expect( variables.calendar.cutoff( variables.task ) ).toBeGT( variables.calendar.epoch() );
            } );
            it( "accepts native frequency arguments and zero-argument shortcuts", () => {
                variables.calendar.configureTask(
                    variables.task,
                    { "cadence": "every", "arguments": [ 5, "minutes" ] }
                );
                expect( variables.task.getPeriod() ).toBe( 5 );
                expect( variables.task.getTimeUnit() ).toBe( "minutes" );
                variables.calendar.configureTask( variables.task, "everyMonth" );
                expect( variables.task.getDayOfTheMonth() ).toBe( 1 );
            } );
            it( "lets a closure use the full fluent scheduler API", () => {
                variables.calendar.configureTask( variables.task, ( task ) => task
                    .onWeekdays( "09:00" )
                    .withNoOverlaps()
                    .when( () => false ) );
                expect( variables.task.getWeekdays() ).toBeTrue();
                expect( variables.task.getNoOverlaps() ).toBeTrue();
                expect( variables.task.isConstrained() ).toBeTrue();
            } );
            it( "copies an unstarted task template without starting or calling its target", () => {
                var template = new coldbox.system.async.tasks.ScheduledTask( "template", {} )
                    .setTimezone( "UTC" )
                    .everyWeekOn( 3, "11:00" );
                variables.calendar.configureTask( variables.task, template );
                expect( variables.task.getTimezone().getId() ).toBe( "UTC" );
                expect( variables.task.getDayOfTheWeek() ).toBe( 3 );
                expect( variables.task.getScheduled() ).toBeFalse();
            } );
            it( "persists and restores a native task instance without executable state", () => {
                var original = new coldbox.system.async.tasks.ScheduledTask( "template", {} )
                    .setTimezone( "UTC" )
                    .everyWeekOn( 4, "10:00" );
                var saved = deserializeJSON( serializeJSON( variables.calendar.normalize( original ) ) );
                variables.calendar.configureTask( variables.task, saved );
                expect( variables.task.getDayOfTheWeek() ).toBe( 4 );
                expect( variables.task.getPeriod() ).toBe( 604800 );
                expect( variables.calendar.cutoff( variables.task ) ).toBeGT( variables.calendar.epoch() );
            } );
            it( "uses native timezone validation and rejects unrelated methods", () => {
                expect( () => variables.calendar.timezone( "Somewhere/Invalid" ) ).toThrow();
                expect( () => variables.calendar.configureTask( variables.task, "start" ) ).toThrow( "Megaphone.Digests.InvalidSchedule" );
                expect( () => variables.calendar.configureTask( variables.task, "weekly" ) ).toThrow( "Megaphone.Digests.InvalidSchedule" );
            } );
        } );
    }

}
