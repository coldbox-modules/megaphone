/** A real custom normalizer must retain every per-value normalization call. */
component extends="qb.models.Query.QueryUtils" {

    public any function extractBinding( any value, required any grammar ) {
        var binding = super.extractBinding( argumentCollection = arguments );
        if (
            isStruct( binding ) && isSimpleValue( binding.value ?: "" ) && left( binding.value ?: "", 10 ) == "normalize:"
        ) {
            binding.value = "normalized:" & mid( binding.value, 11, len( binding.value ) );
        }
        return binding;
    }

}
