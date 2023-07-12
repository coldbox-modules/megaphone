component accessors="true" {

	property name="channel";
	property name="qb";

	property name="page";
	property name="maxRows";
	property name="results";
	property name="pagination";

	public DatabaseNotificationCursor function configureQuery( required function callback ) {
		callback( variables.qb );
		return this;
	}

	public DatabaseNotificationCursor function fetch() {
		var res = variables.qb
			.clone()
			.orderByDesc( "createdDate" )
			.paginate( variables.page, variables.maxRows );
		variables.pagination = res.pagination;
		variables.results    = res.results.map( ( row ) => {
			return newMegaphoneDatabaseNotification().setChannel( getChannel() ).populateFromDatabaseRow( row );
		} );
		return this;
	}

	public boolean function hasNext() {
		return variables.page < variables.pagination.totalPages;
	}

	public DatabaseNotificationCursor function next() {
		if ( variables.page == variables.pagination.totalPages ) {
			throw(
				type         = "Megaphone.DatabaseNotificationCursor.MaximumPageReached",
				message      = "You are already on the last page of results.  Check the `hasNext` method before calling `next` to avoid this exception.",
				extendedInfo = serializeJSON( variables.pagination )
			);
		}

		variables.page++;
		fetch();
		return this;
	}

	public boolean function hasPrevious() {
		return variables.page > 1;
	}

	public DatabaseNotificationCursor function previous() {
		if ( variables.page == 1 ) {
			throw(
				type         = "Megaphone.DatabaseNotificationCursor.MinimumPageReached",
				message      = "You are already on the first page of results.  Check the `hasPrevious` method before calling `previous` to avoid this exception.",
				extendedInfo = serializeJSON( variables.pagination )
			);
		}

		variables.page--;
		fetch();
		return this;
	}

	public DatabaseNotificationCursor function markAllAsRead( date readDate = now() ) {
		variables.qb.clone().update( { "readDate" : arguments.readDate } );
		return this;
	}

	public DatabaseNotificationCursor function deleteAll() {
		variables.qb.clone().delete();
		return this;
	}

	private DatabaseNotification function newMegaphoneDatabaseNotification() provider="DatabaseNotification@megaphone" {
	}

}
