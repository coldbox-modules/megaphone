/** These checks perform local reads only and fail closed on consent and domain visibility. */
interface displayName="IEmailDigestPolicy" {

    /**
     * Checks authoritative consent and admission policy before collection.
     * @returns boolean
     */
    public boolean function canCollect( required any notifiable, required struct definition, required struct item );
    /**
     * Checks the current consent and recipient eligibility for this named subscription.
     * @returns boolean
     */
    public boolean function canSend( required any notifiable, required struct definition, required struct subscription );
    /**
     * Checks current item visibility and eligibility for this Notifiable.
     * @returns boolean
     */
    public boolean function isEligible( required any notifiable, required struct definition, required struct item );

}
