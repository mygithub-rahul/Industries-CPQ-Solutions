
global with sharing class CustomPricingPlanStepImpl implements vlocity_cmt.VlocityOpenInterface, callable 
{
    
    private static String nsp = 'vlocity_cmt__';
    Map<String,String> relatedsourceprods = new Map<String,String>();
    Map<String,String> sourcerelatedprods = new Map<String,String>();
    Map<Id,QuoteLineItem> qliMap = new Map<Id,QuoteLineItem>();
    
    global Boolean invokeMethod (String methodName,
                                 Map<String, Object> input,
                                 Map<String, Object> output,
                                 Map<String, Object> options)
    {
        
        
        if (methodName == 'GetMatrixPrice')
        {
            getMatrixPrice(input, output, options);
        }
        else if(methodName == 'getRefreshOnlyPassedLineItems')
        {
            getRefreshOnlyPassedLineItems(input, output, options);
        }
        
        return true;
    }
    
    public Object call(String action, Map<String, Object> args) 
    {
        Map<String,Object> inputMap = (Map<String,Object>)args.get('input');
        Map<String,Object> outputMap = (Map<String,Object>)args.get('output');
        Map<String,Object> options = (Map<String,Object>)args.get('options');
        
        return invokeMethod(action, inputMap, outputMap, options);
    }
    
    private void getMatrixPrice(Map<String, Object> input,
                                Map<String, Object> output,
                                Map<String, Object> options)
    {
        //system.debug('*****11111111******'+input);
        SObject parent = (SObject)vlocity_cmt.PricingPlanService.getFromPricingContext('Parent');
        //system.debug('*****11111112******'+parent);
        if(input.get('RunOnlyForRecordTypes') != NULL && parent.get('RecordTypeId') != NULL)
        {
            //system.debug('*****11111113******'+input.get('RunOnlyForRecordTypes'));
            List<String> recordTypesNames = new List<String>();
            for(Object recordTypeName : (List<Object>) input.get('RunOnlyForRecordTypes'))
            {
                recordTypesNames.add((String) recordTypeName);
            }
            Id parentRecordTypeId = (Id) parent.get('RecordTypeId');
            String parentSObjectType = String.valueof(parent.getSObjectType());
            List<RecordType> matchedRecordType = [SELECT Id, Name from RecordType WHERE SObjectType =: parentSObjectType AND Name IN: recordTypesNames AND Id =: parentRecordTypeId];
            //Skip the step silently as it is not meant to run for passed parent recordtype.
            if(matchedRecordType.isEmpty())
            {
                return;
            }
        }
        
        List<SObject> itemList = (List<SObject>)vlocity_cmt.PricingPlanService.getFromPricingContext('LineItemList');
        //system.debug('*****11111114******'+itemList);
        Map<Id,Product2> prods = new Map<Id,Product2>([Select Id,Name,ProductCode from Product2 where isActive=true]);
        if(!Test.isRunningTest()){
            updateDeviceDetails(itemList,prods);
        }
        //If Asset or if there are no items, then return
        if(parent == null || itemList == null || itemList.isEmpty()) return;
        
        String sourceTargetABP = (String)input.get('SourceTargetABP');
        boolean runForPassedItemListContext = false;
        if(input.get('RunForPassedItemListContext') != NULL)
        {
            runForPassedItemListContext = (boolean) input.get('RunForPassedItemListContext');
        }
        
        String strDelta = PricingPlanHelper.getCpqConfigurationSetupValue('DeltaPrice');
        
        //CMT-3332 : If Delta Price is TRUE and if source target attribute based pricing is being done, then load all the line items
        if(strDelta.equalsIgnoreCase('True') && sourceTargetABP != NULL && sourceTargetABP.equalsIgnoreCase('True') && !runForPassedItemListContext)
        {
            itemList = getAllLineItems(parent, parent.getSObjectType(), itemList[0].getSObjectType());
            vlocity_cmt.PricingPlanService.putInPricingContext('LineItemList',itemList);
        } 
        else if(runForPassedItemListContext)
        {
            Map<String,Object> inputMap = new Map<String, Object>();
            Map<String,Object> outputMap = new Map<String, Object>();
            Map<String,Object> optionMap = new Map<String, Object>();
            
            //itemList = getRefreshOnlyPassedLineItems(itemList, itemList[0].getSObjectType());
            inputMap.put('lineItems', itemList);
            inputMap.put('lineItemTypeForPage', itemList[0].getSObjectType());
            getRefreshOnlyPassedLineItems(inputMap, outputMap, optionMap);
            
            itemList = (List<Sobject>) outputMap.get('lineItems');
            //System.debug('#####itemlist##'+itemList);
            vlocity_cmt.PricingPlanService.putInPricingContext('LineItemList',itemList);
        }
        
        // If this is the first getMatrixPrice step, clear the external price flag
        Boolean clearExternalPriceFlag = (Boolean)vlocity_cmt.PricingPlanService.getFromPricingContext('ClearExternalPriceFlag');
        if (clearExternalPriceFlag == null )
        {
            clearExternalPriceFlag = true;
            // Do not clear the external price flag for subsequent calls to getMatrixPrice
            vlocity_cmt.PricingPlanService.putInPricingContext('ClearExternalPriceFlag', false);
        }
        
        Map<String, object> priceHelperInput = new Map<String, object>();
        Map<String, object> priceHelperOutput = new Map<String, object>();
        Map<String, object> priceHelperOptions = new Map<String, object>();
        priceHelperInput.put('Parent', parent);
        priceHelperInput.put('ItemList', itemList);
        priceHelperInput.put('ClearExternalPriceFlag', clearExternalPriceFlag);
        priceHelperInput.putAll(input);
        
        // create the matrix input rows from the itemList
        PricingPlanHelper priceHelper = new PricingPlanHelper();
        
        Map<String, Object> agrs = new Map<String, Object>();
        agrs.put('input',priceHelperInput);
        agrs.put('output',priceHelperOutput);
        agrs.put('options',priceHelperOptions);
        //system.debug('*****11111115******'+priceHelperInput);
        priceHelper.call('GetCalculationProcedurePrice', agrs);
        //priceHelper.invokeMethod('GetCalculationProcedurePrice', priceHelperInput, priceHelperOutput, priceHelperOptions);
        //system.debug('*****11111115111******'+priceHelperOutput);
        if (priceHelperOutput.get('error') != null)
        {
            output.put('error', priceHelperOutput.get('error'));
        }
    }
    
    //Querying all the dat
    private List<SObject> getAllLineItems(SObject parent, SobjectType parentObjectTypeForPage, SObjectType lineItemTypeForPage)
    {
        Id parentId = (Id)parent.get('Id');
        String query = getSelectClauseForLIQuery(lineItemTypeForPage) + 
            ' FROM ' + lineItemTypeForPage + ' WHERE ' + parentObjectTypeForPage + 'Id = \'' + parentId + '\'';
        return Database.query(query);
    }
    
    
    //Querying only passed line item in context
      @TestVisible
    private void getRefreshOnlyPassedLineItems(Map<String, Object> inputMap, Map<String, Object> outputMap, Map<String, Object> optionMap)
    {
        List<SObject> lineItems = (List<SObject>) inputMap.get('lineItems');
        SObjectType lineItemTypeForPage = (SObjectType) inputMap.get('lineItemTypeForPage');
        
        Set<Id> itemids = (new Map<Id,SObject>(lineItems)).keySet();
        String query = getSelectClauseForLIQuery(lineItemTypeForPage) +
            ' FROM ' + lineItemTypeForPage + ' WHERE Id IN : itemids';
        outputMap.put('lineItems' , Database.query(query));
    }
    
    private String getSelectClauseForLIQuery(SObjectType lineItemTypeForPage)
    {
        String selectClause = 'Select Id, ' + nsp + 'LineNumber__c, PriceBookEntry.Product2.Name, PriceBookEntry.Product2.ProductCode, PriceBookEntry.Product2.'+ nsp +'AttributeMetadata__c, Product2.'+ nsp +'AttributeMetadata__c, PriceBookEntry.Product2.Id,' +
            'PriceBookEntry.Product2.' + nsp + 'Type__c, PriceBookEntryId, PriceBookEntry.Pricebook2Id, ListPrice, UnitPrice, Quantity,' +
            'PriceBookEntry.Product2.' + nsp + 'JSONAttribute__c,' + nsp + 'jsonattribute__c,' + nsp + 'OneTimeCharge__c, ' +
            nsp + 'JSONNode__c, ' + nsp + 'PricingLogData__c, ' + nsp + 'Query__c, '  + nsp + 'Filter__c, ' + nsp + 'OneTimeCalculatedPrice__c,' +
            nsp + 'OneTimeManualDiscount__c, ' + nsp + 'OneTimeTotal__c, ' + nsp + 'ProductHierarchyPath__c, ' + nsp + 'RecurringCharge__c,' +
            nsp + 'RecurringCalculatedPrice__c, ' + nsp + 'RecurringManualDiscount__c, ' + nsp + 'RecurringDiscountPrice__c, ' + nsp + 'RecurringTotal__c,' +
            nsp + 'RootItemId__c, ' + nsp + 'ParentItemId__c, ' + nsp + 'CpqMessageData__c, ' + nsp + 'CurrencyPaymentMode__c,' +
            nsp + 'CpqCardinalityMessage__c, ' + nsp + 'ProvisioningStatus__c, ' + nsp + 'ServiceAccountId__r.Name, ' + nsp + 'ServiceAccountId__r.Id,' +
            nsp + 'BillingAccountId__r.Name, ' + nsp + 'BillingAccountId__r.Id, ' + nsp + 'Action__c, ' + nsp + 'SubAction__c, ' 
            + 'Product2.' + nsp +'GlobalKey__c, ' +  'Product2.' + nsp +'CategoryData__c, ' +
            + 'PriceBookEntry.Product2.' + nsp +'GlobalGroupKey__c, ' +
            + nsp + 'AttributeSelectedValues__c, ' +
            + 'PriceBookEntry.Product2.' + nsp + 'GlobalKey__c, ' +
            + 'Product2.' + nsp + 'GlobalGroupKey__c ' ;
        if(String.valueof(lineItemTypeForPage) == 'QuoteLineItem')
        {
            selectClause += ( ' ,'+ nsp + 'QuoteMemberId__c ' );
        }
        else if(String.valueof(lineItemTypeForPage) == 'OrderItem')
        {
            selectClause += ( ' ,'+ nsp + 'OrderMemberId__c ' );
        }
        return selectClause;
    }
    @TestVisible
    private void updateDeviceDetails(List<SObject> itemList, Map<Id,Product2> prods){
        
        Set<Id> QliIds = new Set<Id> ();
        
        for (SObject sObj : itemList) {
            Id lineitemId = (Id)sObj.get('Id');
            Id ProductId = getProductId(sObj);
            
            if (prods.containsKey(productId)) {
                String ProductCode = prods.get(ProductId).ProductCode;
                if(ProductCode == 'B2B_MOB_PDT_DC' || ProductCode == 'B2B_MOB_PDT_DIC'){
                    QliIds.add(lineitemId);
                }
            }
        }
        
        if (!QliIds.isEmpty()) {
            List<vlocity_cmt__QuoteLineItemRelationship__c> QliRelationships = [select id,vlocity_cmt__QuoteLineItemId__c,vlocity_cmt__RelatedQuoteLineItemId__c from vlocity_cmt__QuoteLineItemRelationship__c where vlocity_cmt__QuoteLineItemId__c IN:QliIds];
            if(!QliRelationships.isEmpty()){
                for(vlocity_cmt__QuoteLineItemRelationship__c qir : QliRelationships){
                    QliIds.add(qir.vlocity_cmt__RelatedQuoteLineItemId__c);
                    relatedsourceprods.put(qir.vlocity_cmt__RelatedQuoteLineItemId__c,qir.vlocity_cmt__QuoteLineItemId__c);
                    sourcerelatedprods.put(qir.vlocity_cmt__QuoteLineItemId__c,qir.vlocity_cmt__RelatedQuoteLineItemId__c);
                }
                qliMap= new Map<Id,QuoteLineItem>([select id,Product2Id,Product2.ProductCode, vlocity_cmt__AttributeSelectedValues__c, vlocity_cmt__OneTimeCharge__c  from QuoteLineItem where Id IN:QLIIds]);
                for (SObject sObj : itemList) {
                    Id lineitemId = (Id)sObj.get('Id');
                    Id ProductId = getProductId(sObj);
                    String ProductCode = prods.get(ProductId).ProductCode;
                    if(relatedsourceprods.containsKey(lineitemId)){
                        QuoteLineItem qli = qliMap.get(relatedsourceprods.get(lineitemId));
                        if (qli != null && qli.Product2.ProductCode == 'B2B_MOB_PDT_DC' ) {
                            String attributeSelectedValues = (String)sObj.get('vlocity_cmt__AttributeSelectedValues__c');
                            Map<String, Object> relatedattributeValues = new Map<String,Object>();
                            Map<String, Object> sourcerelatedattributeValues = new Map<String,Object>();
                            if(relatedattributeValues!=null && sourcerelatedattributeValues!=null){
                                relatedattributeValues = (Map<String, Object>)JSON.deserializeUntyped(attributeSelectedValues);
                                sourcerelatedattributeValues = (Map<String, Object>)JSON.deserializeUntyped(qli.vlocity_cmt__AttributeSelectedValues__c);
                            }
                            if (relatedattributeValues != null && relatedattributeValues.containsKey('B2B_MOB_ATT_Tier') &&
                                sourcerelatedattributeValues != null && sourcerelatedattributeValues.containsKey('B2B_MOB_ATT_Tier')) {
                                    relatedattributeValues.put('B2B_MOB_ATT_Tier', sourcerelatedattributeValues.get('B2B_MOB_ATT_Tier'));
                                    //System.debug('relatedattributeValues----->'+relatedattributeValues);
                                    sObj.put('vlocity_cmt__AttributeSelectedValues__c',JSON.serialize(relatedattributeValues));
                                }
                        }
                        else if (qli != null && qli.Product2.ProductCode == 'B2B_MOB_PDT_DIC' ) {
                            String relatedAttributeselectedValues = (String)sObj.get('vlocity_cmt__AttributeSelectedValues__c');
                            Map<String, Object> relatedattributeValues = new Map<String, Object>();
                            Map<String, Object> sourceAttributeValues = new Map<String, Object>();
                            if(relatedAttributeselectedValues != null && qli.vlocity_cmt__AttributeSelectedValues__c!=null){
                                sourceAttributeValues = (Map<String, Object>)JSON.deserializeUntyped(qli.vlocity_cmt__AttributeSelectedValues__c);
                                relatedAttributeValues = (Map<String, Object>)JSON.deserializeUntyped(relatedAttributeselectedValues);
                            }
                            if (sourceAttributeValues != null && sourceAttributeValues.containsKey('B2B_MOB_ATT_Tier') && relatedAttributeValues!=null && relatedAttributeValues.containsKey('B2B_MOB_ATT_Tier')) {
                                relatedAttributeValues.put('B2B_MOB_ATT_Tier', sourceAttributeValues.get('B2B_MOB_ATT_Tier'));
                                //System.debug('relatedattributeValues----->'+sourceAttributeValues.get('B2B_MOB_ATT_Tier'));
                                sObj.put('vlocity_cmt__AttributeSelectedValues__c',JSON.serialize(relatedattributeValues));
                            }
                        }
                    }                     
                }
            }  
        } 
    }
    @TestVisible
    private string getProductId(Sobject sObj){
        Id ProductId;
        if(sObj.getPopulatedFieldsAsMap().containsKey('vlocity_cmt__Product2Id__c')){
            ProductId = (Id)sObj.get('vlocity_cmt__Product2Id__c');
        }
        else if(sObj.getPopulatedFieldsAsMap().containsKey('Product2Id')){
            ProductId = (Id)sObj.get('Product2Id');
        }
        return ProductId;  
    }
}