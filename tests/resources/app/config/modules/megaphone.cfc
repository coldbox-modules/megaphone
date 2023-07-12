component {

	function configure(){
		return {
			"channels" : {
				"database" : {
					"provider"   : "DatabaseProvider@megaphone",
					"properties" : {
						"tableName"  : "megaphone_notifications",
						"datasource" : "megaphone"
					}
				}
			}
		};
	}

}
