/**
 * Created by scweber on 7/5/18.
 */

/**
 * There are three email addresses associated with this handler
 * ric-support@stanford.edu will be used by the RIC (their old email will continue to work for now)
 * redcap-help@stanford.edu may eventually be used by the REDCap team
 * rit-support@stanford.edu may eventually be a catch-all for the rest of Research IT
 */
global class SMEmailService implements Messaging.InboundEmailHandler {
    private static final String TAG_REGEX = '@([\\w-]+)+(?:(?:=|\\s?=\\s?)([\\w\\d\\.,_-]+|\\{.*|\\[.*))?';
    public static Set<String> VALID_TAGS = new Set<String>{'open','close','assign','labor','hidden','hide','private','info'};
    // Regex courtesy of http://emailregex.com/
    private static final String EMAIL_REGEX = '(?:[a-z0-9!#$%&\'*+/=?^_`{|}~-]+(?:\\.[a-z0-9!#$%&\'*+/=?^_`{|}~-]+)*|"(?:[\\x01-\\x08\\x0b\\x0c\\x0e-\\x1f\\x21\\x23-\\x5b\\x5d-\\x7f]|\\\\[\\x01-\\x09\\x0b\\x0c\\x0e-\\x7f])*")@(?:(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?|\\[(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?|[a-z0-9-]*[a-z0-9]:(?:[\\x01-\\x08\\x0b\\x0c\\x0e-\\x1f\\x21-\\x5a\\x53-\\x7f]|\\\\[\\x01-\\x09\\x0b\\x0c\\x0e-\\x7f])+)\\])';

    private static final String END_NEW_MESSAGE_INDICATOR = '====== Please type any reply above this line ======';
    private static final String NEW_CASE_SUBJECT  = 'base64_encoded';
    private static final String JSON_PREFIX  = '{"LastName":';
    public static final String SUBJECT_PREFIX  = 'Project_Record_ID__c='; // public for testing
    public static final String STATE_ARCHIVED = 'Archived';
    private static final String EMAIL_TEMPLATE_CUSTOMER_ACK_NEW_RIC = 'CUSTOMER_ACK_NEW_CASE_RIC';
    private static final String EMAIL_TEMPLATE_CUSTOMER_ACK_NEW_RIT = 'CUSTOMER_ACK_NEW_CASE_RIT';
    private static final String EMAIL_TEMPLATE_CASE_NOTIFY_NEW_COMMENT = 'CASE_NOTIFY_NEW_COMMENT';
    private static final String EMAIL_TEMPLATE_ACTION = 'CONSULTANT_ACTION_TAG_STATUS';
    private static final String EMAIL_TEMPLATE_INFO = 'CONSULTANT_INFO';
    private static final String EMAIL_TEMPLATE_CONSULTANT_NEW_CASE_NOTIFICATION = 'CONSULTANT_NEW_CASE_NOTIFICATION';
    private static final String EMAIL_TEMPLATE_CUSTOMER_NACK_UNRECOGNIZED = 'CUSTOMER_NACK_UNRECOGNIZED';
    private static final String EMAIL_TEMPLATE_CUSTOMER_NACK_ARCHIVED = 'CUSTOMER_NACK_ARCHIVED';

    private static final String QN_REDCAP = 'REDCap Queue';
    private static final String QN_RESEARCH_IT = 'Research IT Queue';
    private static final String QN_RIC = 'Consult Request Queue';
    private static final String QUEUE_REDCAP = 'queuename='+QN_REDCAP+';shortname=REDCap Help;longname=REDCap Support;url=http://redcap.stanford.edu/redcap/plugins/gethelp/redcap-support.html;email=redcap-help@stanford.edu';
    private static final String QUEUE_RESEARCH_IT = 'queuename='+QN_RESEARCH_IT+';shortname=Research IT;longname=Research IT;url=http://redcap.stanford.edu/redcap/plugins/gethelp/rit-support.html;email=rit-support@stanford.edu';
    private static final String QUEUE_RIC = 'queuename='+QN_RIC+';shortname=RIC;longname=Research Informatics Center;url=https://med.stanford.edu/ric/;email=ric-support@stanford.edu';

    Boolean sendCaseCommentToCustomer = false;
    private String statusMessage   = '';
    private String latestComment  = '';
    public Case theCase = null; /* public for test case coverage */
    public User invokingUser = null; /* public for test case coverage */
    public Messaging.InboundEmail email; /* public for test case coverage */
    private Map<String,String> orgProperties = new Map<String,String>();
    public String respondent = '';
//    private String preselectedQueue = '';

    public void setSendCaseCommentToCustomer(boolean sendCaseCommentToCustomer) {
        this.sendCaseCommentToCustomer = sendCaseCommentToCustomer;
    }

//    public void setPreselectedQueue(String queueName) {
//        this.preselectedQueue = queueName;
//    }

    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail inboundEmail, Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        this.email = inboundEmail;
        Integer subjectPrefixLen = SUBJECT_PREFIX.length();
        String subject = email.subject;

        if ('Undelivered Mail Returned to Sender'.equals(email.subject)) {
            // code green auto-notifications -  discard silently.
            return result;
        }
        System.debug('subject is ' + subject);
        System.debug('email is from ' + inboundEmail.fromAddress);
        System.debug('email replyTo ' + inboundEmail.replyTo);
        System.debug('addressee is ' + inboundEmail.toAddresses);
        System.debug('cc list is ' + flattenStringArray(inboundEmail.ccAddresses));
        System.debug(' list for inference ' + flattenStringArray(inboundEmail.toAddresses)+' '+ flattenStringArray(inboundEmail.ccAddresses));
        // the first serious possibility to consider is that this is a submission from a web intake form
        // that references an existing case
        if (String.isNotBlank(subject) && subject.length() > SUBJECT_PREFIX.length() && SUBJECT_PREFIX.equals(subject.substring(0, subjectPrefixLen))) {
            try {
                theCase = (Case)getCaseByRedcapId(subject.substring(subjectPrefixLen));
                if (theCase == null) {
                    callForHelp( 'Unable to locate case '+subject+' , please contact customer support');
                } else {
                    parseQueue(theCase.Active_Queue__c);
                    attachCommentToCase(email.plainTextBody, true);
                }
            } catch (Exception e) {
                callForHelp( 'Unable to retrieve case: ' + email.subject + ' \n' + e.getMessage() + ' ' + e.getCause() + ' on line ' + e.getLineNumber());
            }
            return result;
        }

        Integer jsonPrefixLen = JSON_PREFIX.length();
        String body = email.plainTextBody;
        // the next serious possibility to consider is that this is a submission from a web intake form
        // that specifies a brand new case
        if (String.isNotBlank(email.subject) && NEW_CASE_SUBJECT.equals(email.subject)) {
            body = EncodingUtil.base64Decode(body.replaceAll('(\\r|\\n|\\s)+','')).toString();
        }
        System.debug('2- body is now '+body);
        if (String.isNotBlank(body) && body.length() > jsonPrefixLen && JSON_PREFIX.equals(body.substring(0, jsonPrefixLen))) {
            try {
                // because the REDCap emailer seems to break up the email into lines,
                // strip out all unescaped newlines before proceeding
//                Pattern lineBreaks = Pattern.compile('[\n\r]');
//                body = lineBreaks.matcher(body).replaceAll('');
                body =  body.replaceAll('(\\r|\\n)+','');
                System.debug('creating a new case from body ' + body);

                String [] jsonStrings = body.split('~#~#~');
                System.debug('# strings found '+jsonStrings.size());
                // Production REDCap is inserting newlines where none should exist
                // so before proceeding glue everything back together again
                Contact theContact = (Contact) JSON.deserialize(jsonStrings[0], Contact.class);
                //  upsert theContact;  just calling upsert creates duplicates, so we have to roll our own lookup
                homebrewUpsert(theContact);

                theCase = (Case) JSON.deserialize(jsonStrings[1], Case.class);
                System.debug('newly created case description is ' + theCase.Description);
                trimCaseToFit();
                theCase.ContactId = theContact.Id;

                System.debug ('line 119 theCase.Active_Queue__c ' + theCase.Active_Queue__c);
                // this populates the orgProperties map used by many of the templated email responses
                // to see what strings show up in Active_Queue__c just check the source for
                // https://redcap.stanford.edu/plugins/gethelp/ric.php, rit.php and redcap.php
                if (theCase.Active_Queue__c == null || ''.equals(theCase.Active_Queue__c)) {
                    theCase.Active_Queue__c = inferQueueFromAddressee();
                }
                System.debug ('line 126 theCase.Active_Queue__c ' + theCase.Active_Queue__c);
                parseQueue(theCase.Active_Queue__c);

                String queueName = orgProperties.get('queuename');
                System.debug('looking up queue by name ' + queueName);
                List<Group> groupIdList = [SELECT Id, Name FROM Group WHERE Type = 'Queue' AND Name = :queueName];
                System.debug('looking for owner ; found queue '+groupIdList);
                if (!groupIdList.isEmpty()) {
                    System.debug('bingo, assigning case ownership to this queue');
                    theCase.OwnerId = groupIdList.get(0).Id;
                }

//                theCase.Server_Message_Plain__c = email.plainTextBody;
                insert theCase;

                // now retrieve it to get the values for the auto-populated fields such as reference__c and Status
                theCase = getCaseById(theCase.Id);
                updateRedcap(theCase.CaseNumber, theCase.Status, theCase.Owner.Name ,true, theCase.Active_Queue__c, theCase.Project_Record_ID__c);
                latestComment = '' ;
                // this should reliably work
                notify((String[]) getEmailByQueueName(queueName), new String[] {}, new String[] {'scweber@stanford.edu'}, selectTemplate(EMAIL_TEMPLATE_CONSULTANT_NEW_CASE_NOTIFICATION));

                // only send out the courtesy notice if the party named as the primary contact is *not* a salesforce user
                // getSFUser will return null if the supplied email address does not correspond to a SF user
                if (getSFUser(email.fromAddress) == null) {
                    // this however may trigger an exception if the supplied contact email address was mistyped
                    if (orgProperties.get('shortname').equals('RIC')) {

                        notify(email.fromAddress, email.ccAddresses, new String[] {'scweber@stanford.edu'}, selectTemplate(EMAIL_TEMPLATE_CUSTOMER_ACK_NEW_RIC));
                    } else {
                        notify(email.fromAddress, email.ccAddresses, new String[] {'scweber@stanford.edu'}, selectTemplate(EMAIL_TEMPLATE_CUSTOMER_ACK_NEW_RIT));
                    }
                }

            } catch (Exception e) {
                callForHelp( 'Unable to convert to case: ' + email.plainTextBody + ' \n' + e.getMessage() + ' ' + e.getCause() + ' on line ' + e.getLineNumber());
            }

            return result;
        }

        // at this point we've dealt with the possibility that the body was JSON,
        // so there are now only four possibilities left :
        // 1. the email does not refer to a known case
        // 2. the case has been archived
        // 3. the consultant is responding and possibly specifying some action
        // 4. the customer is commenting
        //
        // let's see if it is a reply to an existing case. this will return null if not found
        theCase = getExistingCase(email);

        if (theCase == null) {
            // if we reach this point it means someone, presumably a customer but not necessarily,
            // has written a new email that does not refer to a known case.
            // we can infer which queue they were trying to reach by inspecting the email address they used
            // rit-support , redcap, and informatics are the three possibilities
            parseQueue(inferQueueFromAddressee());

            // send them a polite note asking them to fill out the web form
            notifySansReplyPrompt(email.replyTo, email.ccAddresses, new String[] {'scweber@stanford.edu'}, selectTemplate(EMAIL_TEMPLATE_CUSTOMER_NACK_UNRECOGNIZED));

            // this next section may or may not be what we want; this sends an email notification to a queue
            // include the customer's email in the version sent to the consultants
//            latestComment = email.plainTextBody;
//            notifySansReplyPrompt(errorQueue(), selectTemplate(EMAIL_TEMPLATE_CUSTOMER_NACK_UNRECOGNIZED));

            return result;
        }

        // this populates the orgProperties map used by many of the templated email responses
        // to see what strings show up in Active_Queue__c just check the source for
        // https://redcap.stanford.edu/plugins/gethelp/ric.php, rit.php and redcap.php
        parseQueue(theCase.Active_Queue__c);

        // at this point we should have a non-null case, so now lets see if it has been archived
        if (STATE_ARCHIVED.equals(theCase.Status)) {

            // TODO it would be very nice if the link in this email contained a reference to the
            // TODO archived case, so when the user clicks on the link to the intake form, the related case field is pre-populated
            // this invocation pattern avoids the 'reply above the line'

            latestComment = allComentsForCase(theCase);
            notifySansReplyPrompt(email.replyTo, email.ccAddresses, new String[] {'scweber@stanford.edu'}, selectTemplate(EMAIL_TEMPLATE_CUSTOMER_NACK_ARCHIVED));
            // include the customer's email in the version sent to the consultants
            // when the next line is commented out, the consultation team is not informed
//            notifySansReplyPrompt(errorQueue(), selectTemplate(EMAIL_TEMPLATE_CUSTOMER_NACK_ARCHIVED));
            return result;
        }

        // not archived? ok good.
        // Pick out the string above the dotted line and stash in 'latestComment' for later
        Integer endPos = ((String) email.plainTextBody).indexOf(END_NEW_MESSAGE_INDICATOR);
        if (endPos <= 0) {
            latestComment = email.plainTextBody;
        } else {
            latestComment = ((String) email.plainTextBody).substring(0, endPos - 1);
        }

        // this is needed to correctly handle the case where the consultant replies with nothing but an action tag
        Pattern replyPattern = Pattern.compile('On (.|\\n)*wrote:(.|\\n)*');
        Matcher myMatcher = replyPattern.matcher(latestComment);
        System.debug('latestComment was ' + latestComment);
        try {
            if (myMatcher.find()) {
                System.debug('find 1');
                System.debug('myMatcher.group(0) ' + myMatcher.group(0));
                System.debug('latest comment was ' + latestComment);
                endPos = latestComment.indexOf(myMatcher.group(0));
                latestComment = latestComment.substring(0, endPos - 1).trim();
            }
        } catch (Exception probableStackOverflow) {
            System.debug('ERROR '+probableStackOverflow.getMessage());
        }
        // after stripping out the reply header in the body and the action tags, nothing may be left
        System.debug('latestComment is now ' + latestComment);

        // now we just need to figure out who sent it, a consultant or a customer
        invokingUser = getSFUser(email.fromAddress);
        System.debug('invokingUser is '+invokingUser);
        if (invokingUser != null) {
            // the consultant is responding and possibly specifying some action

            Boolean isPublicComment = executeActionTags(latestComment);

            latestComment = removeTags(latestComment).trim();
            System.debug('latestComment after removing tags is ' + latestComment);
            System.debug('latestComment length is ' + latestComment.length());
            System.debug('latestComment indexof > is ' + latestComment.indexOf('>'));
            System.debug('latestComment indexof tab is ' + latestComment.indexOf('\t'));

            // if there is a comment notification
            if (latestComment.length() > 0) {

                attachCommentToCase(latestComment, false); // important! do not notify the owner - changing false to true here leads to an infinite notification loop

                // if it should go out to the customer, send it
                // note the while sendCaseCommentToCustomer is initialized to false, there is a constructor
                // that sets it to true that is invoked by the REDCapEmailHandler
                System.debug('considering sending comment to case ' + sendCaseCommentToCustomer+' '+isPublicComment);
                if (sendCaseCommentToCustomer && isPublicComment) {
                    respondent = orgProperties.get('longname');
                    latestComment = allComentsForCase(theCase);
                    System.debug('notifying customer! ' + latestComment);
                    notify(theCase.Contact.Email, email.ccAddresses, new String[] {'scweber@stanford.edu', email.fromAddress}, selectTemplate(EMAIL_TEMPLATE_CASE_NOTIFY_NEW_COMMENT));
                }
            }

        } else {
            System.debug('which means we think this is the customer, not a consultant');
            // the customer is responding.
            if (latestComment.length() > 0) {
                attachCommentToCase(latestComment, true);
            }
        }

        return result;
    }

    private String inferQueueFromAddressee() {
        String inferredQueue;
        String addressees = flattenStringArray(email.toAddresses)+' '+ flattenStringArray(email.ccAddresses) +' '+email.fromAddress;
        System.debug('addressees ' + addressees);

        if (addressees.containsIgnoreCase('informatics')) {
            inferredQueue = QUEUE_RIC;
        } else if (addressees.containsIgnoreCase('yelena')) {
            inferredQueue = QUEUE_RIC;
        } else if (addressees.containsIgnoreCase('eileen')) {
            inferredQueue = QUEUE_RIC;
        } else if (addressees.containsIgnoreCase('anna') || addressees.containsIgnoreCase('graber')) {
            inferredQueue = QUEUE_RIC;
        } else if (addressees.containsIgnoreCase('sabrina')) {
            inferredQueue = QUEUE_RIC;
        } else if (addressees.containsIgnoreCase('steph')) {
            inferredQueue = QUEUE_RIC;
        } else if (addressees.containsIgnoreCase('mina')) {
            inferredQueue = QUEUE_RIC;
        } else if (addressees.containsIgnoreCase('archana')) {
            inferredQueue = QUEUE_RIC;
        } else if (addressees.containsIgnoreCase('andy')) {
            inferredQueue = QUEUE_REDCAP;
        } else if (addressees.containsIgnoreCase('alvaro')) {
            inferredQueue = QUEUE_REDCAP;
        } else if (addressees.containsIgnoreCase('ryan')) {
            inferredQueue = QUEUE_REDCAP;
        } else if (addressees.containsIgnoreCase('jae')) {
            inferredQueue = QUEUE_REDCAP;
        } else if (addressees.containsIgnoreCase('redcap')) {
            inferredQueue = QUEUE_REDCAP;
        } else if (addressees.containsIgnoreCase('rit-support')) {
            inferredQueue = QUEUE_RESEARCH_IT;
        } else if (addressees.containsIgnoreCase('weber')) {
            inferredQueue = QUEUE_RESEARCH_IT;
        } else if (((String) email.plainTextBody).containsIgnoreCase('redcap') || ((String) email.subject).containsIgnoreCase('redcap') || ((String)email.replyTo).containsIgnoreCase('redcap')) {
            // this would be slightly cleaner if populated in a custom field somewhere
            inferredQueue = QUEUE_REDCAP;
        } else if (((String) email.replyTo).containsIgnoreCase('rit-support')) {
            inferredQueue = QUEUE_RESEARCH_IT;
        } else  {
            System.debug('inferQueueFromAddressee() default queue');
            inferredQueue = QUEUE_RIC;
        }

        return inferredQueue;
    }

    private void callForHelp(String troubleReport) {
        System.debug('trouble creating the case: ' + troubleReport);
        notify(email.replyTo, new String[] {}, new String[]{}, 'SMEmailService Error', troubleReport);
        notify(errorQueue(), new String[] {}, new String[]{}, 'SMEmailService Error', troubleReport);
    }

    private void attachCommentToCase(String customerComment, Boolean notify) {
        // First add their name to the comment since only salesforce users can be assigned to CreatedBy
        latestComment =  getDateAndTime() + ' ' +(email.fromName == null ? email.fromAddress : email.fromName)+ ' wrote:\n' + customerComment;
        String commentForInsertion = latestComment.substring(0, Math.min(latestComment.length(),3800));
        System.debug('new comment length' + commentForInsertion.length());
        CaseComment comment = new CaseComment(CommentBody=commentForInsertion, ParentId=theCase.Id, IsPublished=true);
        // then add their comment to the case
        insert comment;

//        theCase.Server_Message_Plain__c = email.plainTextBody;
        update theCase;

        if (notify) {
            updateRedcap(theCase.CaseNumber, theCase.Status, theCase.Owner.Name, false, theCase.Active_Queue__c, theCase.Project_Record_ID__c);
            // Then notify the case owner, which can be either a person or a queue
            respondent = email.fromName;
            // the case in question may still be owned by the queue,
            // so use the info in the case rather than the reply-to when notifying the consultant(s)
            System.debug('theCase.OwnerId ' + theCase.OwnerId);
            latestComment = allComentsForCase(theCase);
            // XXX TODO the logic here needs work: if the owner is already listed on the email this creates a duplicate
            notify(getEmailByQueueOrUserId(theCase.OwnerId), new String[]{}, new String[]{'scweber@stanford.edu'}, selectTemplate(EMAIL_TEMPLATE_CASE_NOTIFY_NEW_COMMENT));
        }
    }

    private String allComentsForCase(Case aCase) {
        List<CaseComment> commentList = [SELECT Id, CommentBody, CreatedDate FROM CaseComment WHERE ParentId = :theCase.Id ORDER BY CreatedDate DESC] ;
        String allComments = '';
        for (CaseComment aComment : commentList)   {
            allComments += aComment.CommentBody + '\n\n';
        }

        allComments = allComments + 'Original Request:\n' + aCase.Description;
        return allComments.trim();
    }

    public Boolean executeActionTags(String message) {
        Boolean unusualCirumstance = false;
        Boolean redcapNeedsUpdating = false;
        Map<String, String> tagMap = getTags(message);
        System.debug('tags ' + tagMap);

        if (tagMap.keySet().size() == 0) {
            return true;
        }
        statusMessage  = '';

        if(tagMap.keySet().contains('open')) {

            if (theCase.Status == 'Open' &&
                    theCase.Owner != null &&
                    theCase.Owner.Type == 'User' &&
                    theCase.OwnerId != invokingUser.Id) {
                statusMessage += theCase.CaseNumber + ' is already open and assigned to ' +theCase.Owner.Name + '.\n';
                unusualCirumstance = true; // this flag when set triggers an advisory email to the consultant
            } else {
                // if not open or if owned by a queue or if already owned by you (maybe someone else assigned it), take ownership
                theCase.Status = 'Open';
                System.debug('reassigning ownership as part of an @open action: prior owner '+theCase.OwnerId );
                theCase.OwnerId = (invokingUser == null? null:invokingUser.Id);
                System.debug('new owner '+theCase.OwnerId );
                update theCase;
                theCase = getCaseById(theCase.Id);

                redcapNeedsUpdating = true;
                statusMessage += 'You have successfully taken ownership of ' + theCase.CaseNumber + '.\n';
            }
        }

        String queueName = null;
        if(tagMap.keySet().contains('assign')) {
            String newOwnerName = tagMap.get('assign');
            System.debug('reassigning ownership as part of an @assign action: prior owner '+theCase.OwnerId + ' and new owner requested is '+newOwnerName);
            if ('ric'.equalsIgnoreCase(newOwnerName)) {
                queueName = QN_RIC;
                theCase.Active_Queue__c = QUEUE_RIC;

            } else if ('rit'.equalsIgnoreCase(newOwnerName)) {
                queueName = QN_RESEARCH_IT;
                theCase.Active_Queue__c = QUEUE_RESEARCH_IT;

            } else if ('redcap'.equalsIgnoreCase(newOwnerName)) {
                queueName = QN_REDCAP;
                theCase.Active_Queue__c = QUEUE_REDCAP;

            }
            System.debug ('queuename is now ' + queueName);
            if (queueName != null) {

                System.debug('looking up queue by name');
                List<Group> groupIdList = [SELECT Id, Name FROM Group WHERE Type = 'Queue' AND Name = :queueName];
                System.debug(groupIdList);
                if (!groupIdList.isEmpty()) {
                    theCase.OwnerId = groupIdList.get(0).Id;
                    update theCase;
                    theCase = getCaseById(theCase.Id);
                    redcapNeedsUpdating = true;
                    parseQueue(theCase.Active_Queue__c);
                    latestComment = removeTags(message).trim();
                    notify((String[]) getEmailByQueueName(queueName), new String[]{}, new String[]{'scweber@stanford.edu'}, selectTemplate(EMAIL_TEMPLATE_CONSULTANT_NEW_CASE_NOTIFICATION));
                }

            } else {
                User theUser = getSFUser(newOwnerName);
                if (theUser == null) {
                    statusMessage += theCase.CaseNumber + ' has NOT been re-assigned. No match was found for the supplied user ' + tagMap.get('assign') + '.\n';
                    unusualCirumstance = true;
                } else {

                    theCase.OwnerId = theUser.Id;
                    System.debug('new owner ' + theCase.OwnerId);

                    update theCase;
                    theCase = getCaseById(theCase.Id);

                    redcapNeedsUpdating = true;

                    // this is a bit of a special case. the default notification below is pinned to the sender
                    // but in this case the new owner is the person who really needs to hear about this action
                    notifySansReplyPrompt(theUser.Email,  new String[]{}, new String[]{'scweber@stanford.edu'}, selectTemplate(EMAIL_TEMPLATE_CONSULTANT_NEW_CASE_NOTIFICATION));
                }
            }
        }

        if(tagMap.keySet().contains('labor')) {
            try {
                Decimal originalLabor = theCase.Total_Labor__c;
                Decimal labor = Decimal.valueOf(tagMap.get('labor'));
                if (theCase.Total_Labor__c == null) {
                    theCase.Total_Labor__c = labor;
                    originalLabor = 0;
                } else {
                    theCase.Total_Labor__c = theCase.Total_Labor__c + labor;
                }
                update theCase;
                // no reportable fields have changed so no need to refresh the case

                redcapNeedsUpdating = true;
                statusMessage += 'Labor has been updated from ' + originalLabor + ' to ' +theCase.Total_Labor__c + ' for ' + theCase.CaseNumber+ '.\n';
            } catch (Exception e) {
                unusualCirumstance = true;
                System.debug('Unable to convert to case: ' + email.plainTextBody + ' \n' + e.getMessage() +' '+e.getCause()+' on line '+e.getLineNumber());
                statusMessage += 'Problem updating ' + theCase.CaseNumber + 'Labor tag did not include a number (found '+tagMap.get('labor')+').  Correct usage: @labor=2 or @labor=1.5\n';
            }
        }

        if(tagMap.keySet().contains('close')) {
            theCase.Status = 'Closed';
            theCase.Reason = tagMap.get('assign');
            if (theCase.Reason == null) {
                theCase.Reason = 'Complete (Request Fulfilled)';
            }
            update theCase;
            theCase = getCaseById(theCase.Id);

            redcapNeedsUpdating = true;
            statusMessage +=  theCase.CaseNumber + ' has been closed and will be auto-archived if no further activity is seen in the next few weeks.\n';
        }

        if (statusMessage.length() > 0 || latestComment.trim().length() > 0) {
            if (tagMap.keySet().contains('info')) {
                notifySansReplyPrompt(email.fromAddress, email.ccAddresses, new String[]{}, selectTemplate(EMAIL_TEMPLATE_INFO));
            } else if (unusualCirumstance) {
                notifySansReplyPrompt(email.fromAddress,  email.ccAddresses, new String[]{}, selectTemplate(EMAIL_TEMPLATE_ACTION));
                // email.fromAddress handles the case where someone else writes in
                // was getEmailByQueueOrUserId(theCase.OwnerId)
            }
        }

        if (redcapNeedsUpdating) {
            updateRedcap(theCase.CaseNumber, theCase.Status, theCase.Owner.Name, false, theCase.Active_Queue__c, theCase.Project_Record_ID__c);
        }

        return (! tagMap.keySet().contains('assign') && ! tagMap.keySet().contains('hide') &&
                ! tagMap.keySet().contains('hidden') && ! tagMap.keySet().contains('private'));
    }

    private void notify(String address, String[] ccAddress, String[] bccAddress, EmailTemplate template) {
        notify(address, ccAddress, bccAddress, template.Subject, END_NEW_MESSAGE_INDICATOR + '\n\n' + template.Body);
    }

    private void notifySansReplyPrompt(String address, String[] ccAddress, String[] bccAddress, EmailTemplate template) {
        notify(address, ccAddress, bccAddress, template.Subject, template.Body);
    }

    private void notify(String[] toAddresses, String[] ccAddress, String[] bccAddress, EmailTemplate template) {
        notify(toAddresses, ccAddress, bccAddress, template.Subject, END_NEW_MESSAGE_INDICATOR + '\n\n' + template.Body);
    }

    private void notifySansReplyPrompt(String[] toAddresses, String[] ccAddress, String[] bccAddress, EmailTemplate template) {
        notify(toAddresses, ccAddress, bccAddress, template.Subject, template.Body);
    }

    private void notify(String address, String[] ccAddress,  String[] bccAddress, String subject, String message) {
        notify(new String[] {address}, ccAddress, bccAddress, subject, message);
    }

    private void notify(String[] toAddresses, String[] ccAddress, String[] bccAddress, String subject, String message) {
        notify(toAddresses, ccAddress, bccAddress, subject, message, true);
    }

    private void notify(String[] toAddresses, String[] ccAddresses, String[] bccAddresses, String subject, String message, Boolean emailOnException) {
        try {
            Messaging.SingleEmailMessage outbound = new Messaging.SingleEmailMessage();
            System.debug('toAddress field is ' + toAddresses + ' subject is ' + subject + ' and message is ' + message);
            outbound.toAddresses = toAddresses;
            outbound.ccAddresses = ccAddresses;
            outbound.bccAddresses = bccAddresses;
            outbound.setSubject('Re: ' + subject);
            outbound.setPlainTextBody(message);
            outbound.setReplyTo(orgProperties.get('email'));

            if (emailOnException) {
                // i.e. this is the first notification attempt and not the attempt to notify susan of an exception
                // do things in this order to capture as much information in the case as possible even when there is a problem
                List<Attachment> attachments = copyEmailtoCase ( email );
//                saveEmailToCase(subject, message, flattenStringArray(toAddresses), flattenStringArray(bccAddresses), null, null);
                if (attachments != null && attachments.size() > 0) {
                    List<Id> idList = new List<Id>();
                    for (Attachment a:attachments) {
                        System.debug('==> Found attachment: ' + a.Id);
                        idList.add(a.Id);
                    }

                    outbound.setEntityAttachments(idList);

                }
            }
            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{
                    outbound
            });
        } catch (Exception e) {
            System.debug('ERROR line ' +e.getLineNumber()+' '+e.getMessage());
            if (emailOnException) {
                String errorMessage = 'ERROR line ' +e.getLineNumber()+' '+e.getMessage()+'\n\nAttempting to email '
                        +toAddresses+'\n\n'+subject+'\n\n'+message;
                notify(new String[] {'scweber@stanford.edu'}, new String[]{}, new String[]{}, 'Salesforce Error', errorMessage, false);
            }
        }
    }

 /*   private void saveEmailToCase( String subject, String body, String addressee, String bcc, String idOfSFUser, String relationship) {
        if (theCase == null) return;
        EmailMessage emailMessage = new EmailMessage();
//        emailMessage.Status = '3'; // email was sent
        emailMessage.RelatedToId = theCase.Id; // related to
        emailMessage.FromAddress =  orgProperties.get('email'); // from address

        emailMessage.Subject = subject; // email subject
        emailMessage.TextBody =  mySubString(body, 31999); // email body
        emailMessage.ToAddress = addressee;
        emailMessage.BccAddress = bcc;
        insert emailMessage; // insert

        // Add Email Message Relation for id of the sender
        if (idOfSFUser != null && relationship != null) {
            EmailMessageRelation emr = new EmailMessageRelation();
            emr.EmailMessageId = emailMessage.Id;
            emr.RelationId = idOfSFUser; // user id of the sender
            emr.RelationType = relationship;
            insert emr;
        }
    } */

    public List<Attachment> copyEmailtoCase (Messaging.InboundEmail email) {
        List<Attachment> newAttachments = new List<Attachment>();
        if (theCase == null) {
            return newAttachments;
            // no case to copy to so fail fast
        }
        // Takes the inbound email and envelope and uses it to generate a new email including all attachments
        EmailMessage msg = new EmailMessage (
                ToAddress = email.toAddresses[0],
                FromAddress = email.fromAddress,
                FromName = email.fromName,
                Subject =  email.subject,
                TextBody = mySubString(makeDescription(email), 31995),
                HtmlBody = mySubString(email.htmlBody, 31995),
                Incoming = true,
                Status = '0',		//'0' = New,'1' = Read,'2' = Replied,'3' = Sent,'4' = Forwarded
                ParentId = theCase.Id
        );
        insert msg;
        String newEmailId = msg.Id;
        //find attachments
        List<Messaging.InboundEmail.TextAttachment> tAttachments = email.textAttachments;
        List<Messaging.InboundEmail.BinaryAttachment> bAttachments = email.binaryAttachments;

        if (tAttachments != null) {
            for (Messaging.InboundEmail.TextAttachment t:tAttachments) {
                System.debug('==> Found text attachment: ' + t.fileName);
                Attachment a = new Attachment(
                        Body = Blob.valueOf(t.body),
                        Name = t.fileName,
                        ParentId = newEmailId,
                        ContentType = t.mimeTypeSubType
                );
                newAttachments.add(a);
            }
        }
        if (bAttachments != null) {
            for (Messaging.InboundEmail.BinaryAttachment b:bAttachments) {
                System.debug('==> Found binary attachment: ' + b.fileName);
                Attachment a = new Attachment(
                        Body = b.body,
                        Name = b.fileName,
                        ParentId = newEmailId,
                        ContentType = b.mimeTypeSubType
                );
                newAttachments.add(a);
            }
        }
        if (newAttachments.size()>0) {
            insert(newAttachments);
        }
        return newAttachments;
    }

    public static String makeDescription (Messaging.InboundEmail email) {
        String sDesc = '';
        if (NEW_CASE_SUBJECT.equals(email.subject )) {
            sDesc = EncodingUtil.base64Decode(email.plainTextBody.replaceAll('(\\r|\\n|\\s)+','')).toString();
        } else if (email.plainTextBody != '' && email.plainTextBody != null) {
            sDesc = email.plainTextBody;
        } else {
            sDesc = StripHTML(email.htmlBody);
        }
        return sDesc;
    }

    public static String StripHTML(String html) {
        String result = '';
        //This is a poor man's attempt to convert html email content into standard text...
        result = html.replaceAll('\n', '');
        result = result.replaceAll('\r', '');
        result = result.replaceAll('(?i)<(tr|br|ul|p)(| |/| .*?)>', '\n');		//replace tr br ul or p tags (ignore class) with linefeed
        result = result.replaceAll('(?i)</(li|p)>', '\n');				//replace \li or \p with linefeed
        result = result.replaceAll('(?i)<li(| |/| .*?)>', '\t\\* ');	//replace li with tab*
        result = result.replaceAll('(?i)<td(| |/| .*?)>', '\t');		//replace td with tab*
        result = result.replaceAll('(?i)&nbsp;', ' ');
        //regular expression to match all HTML/XML tags
        String HTML_TAG_PATTERN = '<\\w.*?>';							//replace most other html tags with nothing
        Pattern myPattern = Pattern.compile(HTML_TAG_PATTERN);
        Matcher myMatcher = myPattern.matcher(result);
        result = myMatcher.replaceAll('');
        return result;
    }

    public String flattenStringArray (String[] stringArray) {
        String flatString = '';
        if (stringArray == null) {
            return flatString;
        }
        for (Integer i = 0; i < stringArray.size(); i++) {
            flatString = flatString + stringArray[i];
            if (i < stringArray.size() - 1) {
                flatString = flatString + ',';
            }
        }
        return flatString;
    }

    public Case getCaseById(Id caseId) {
        return  [SELECT Id, CaseNumber, Subject, Availability__c, Description, Status, OwnerId, Contact.Id, Contact.FirstName, Contact.LastName, Contact.Name, Contact.Email, reference__c, Owner.Alias, Owner.Name, Owner.Type, Active_Queue__c, Total_Labor__c, Project_Record_ID__c  FROM Case WHERE Id = :caseId];
    }

    public EmailTemplate selectTemplate(String templateName) {
        //  tinker with name - e.g. pick RIC template if toAddress is informaticsconsultation@lists etc
//        Set<String> setAddr = new Set<String>(email.toAddresses);
//        String name = templateName;
        //TODO consider setting up some form of customization e.g. have different SLA statements
//        if (setAddr.contains(RIC_EMAIL)) {
//            name += '_RIC';
//        } else if (setAddr.contains(REDCAP_EMAIL)) {
//            name += '_REDCAP';
//        } else if (setAddr.contains(RESEARCHIT_EMAIL)) {
//            name += '_RIT';
//        }
        EmailTemplate template = null;
        List<EmailTemplate> templateList = [SELECT Id, Name, Subject, Body FROM EmailTemplate WHERE Name=:templateName];
        for(EmailTemplate theTemplate : templateList) {
            template = theTemplate;
//            System.debug('template name '+templateName);
//            System.debug('template.Subject '+template.Subject);
//            System.debug('template.Body '+template.Body);
//            System.debug('email.fromName '+email.fromName);
//            System.debug('email.subject '+email.subject);
//            System.debug('respondent '+respondent);

            // now populate the various substitution strings
            template.Body = template.Body
                    .replace('{customerName}', email.fromName)
                    .replace('{datetime}', getDateAndTime())
                    .replace('{respondent}', respondent);

            if (theCase != null) {
//                System.debug('theCase.Subject ' +theCase.Subject);
//                System.debug('theCase.CaseNumber ' +theCase.CaseNumber);
//                System.debug('theCase.Contact.Name ' +theCase.Contact.Name);
//                System.debug('theCase.reference__c ' +theCase.reference__c);
//                System.debug('theCase.Description ' +theCase.Description);
//                System.debug('theCase.Owner.Alias ' +theCase.Owner.Alias);
//                System.debug('theCase.Owner.Name ' +theCase.Owner.Name);
                template.Body = template.Body
                        .replace('{case}', theCase.CaseNumber)
                        .replace('{ref}', theCase.reference__c)
                        .replace('{description}', (theCase.Description == null ? '' :theCase.Description))
                        .replace('{subject}', theCase.Subject)
                        .replace('{owner}', (theCase.Owner == null ? '' : theCase.Owner.Name))
                        .replace('{url}',  Url.getSalesforceBaseUrl().toExternalForm() + '/' + theCase.Id);

                template.Subject = template.Subject
                        .replace('{subject}', theCase.Subject)
                        .replace('{case}', theCase.CaseNumber);
            } else {

                template.Subject = template.Subject
                        .replace('{subject}', email.subject);
                template.Body = template.Body
                        .replace('{subject}', email.subject);

            }
            if (orgProperties.keySet().size() > 0) {
                System.debug(orgProperties);
                template.Body = template.Body
                        .replace('{org.email}', orgProperties.get('email'))
                        .replace('{org.short}', orgProperties.get('shortname'))
                        .replace('{org.long}', orgProperties.get('longname'))
                        .replace('{org.url}', orgProperties.get('url'))
                        ;
                template.Subject = template.Subject
                        .replace('{org.short}', orgProperties.get('shortname'));
            }
            template.Body = template.Body
                    .replace('{comment}', latestComment)
                    .replace('{consultant}', email.replyTo)
                    .replace('{status}', statusMessage);
        }

        return template;
    }

    // TODO rather than hardcoding, look up a queue of SF users who wish error notification
    private String[] errorQueue() {
        return new String[] {'scweber@stanford.edu'};
    }

    private User getSFUser(String emailOrAlias) {
        Map<String, User> emailToUser = new Map<String, User>();
        List<User> usrList = [SELECT Id, FirstName, LastName, Name, Email, Alias FROM User WHERE IsActive = TRUE];
        for(User usr : usrList) {
            System.debug('adding ' + usr.Email.toLowerCase() + ' and ' +usr.Alias.toLowerCase() + ' to emailToUser map');
            emailToUser.put(usr.Email.toLowerCase(), usr);
            emailToUser.put(usr.Alias.toLowerCase(), usr);
        }
        System.debug('getSFUser emailToUser ' +emailToUser);
        System.debug('getSFUser emailOrAlias' + emailOrAlias);
        System.debug('getSFUser pareDownEmail(emailOrAlias) '+pareDownEmail(emailOrAlias));
        System.debug('getSFUser returning ' + emailToUser.get(pareDownEmail(emailOrAlias.toLowerCase())));
        return emailToUser.get(pareDownEmail(emailOrAlias.toLowerCase()));
    }

    private void parseQueue(String inputString) {
        // theCase.Active_Queue__c comes in the following format
        // queuename=Consult Request Queue;shortname=RIC;longname=Research Informatics Center;url=https://ric-help.med.stanford.edu/;email=ric-support@stanford.edu
//        if (preselectedQueue.equals(QN_REDCAP)) {
//            reallyParseQueue(QUEUE_REDCAP);
//        } else
        if (inputString == null || inputString.length() == 0) {
            System.debug('line 807 inferring queue from addressee ' );
            inputString = inferQueueFromAddressee();
        }
        reallyParseQueue(inputString);
    }

    private void reallyParseQueue(String inputString) {
        List<String> parts = inputString.split(';');
        System.debug('in reallyParseQueue, inputString is '+inputString);
        System.debug('in reallyParseQueue, nparts is '+parts.size());
        for(String pvalue : parts) {
            System.debug('pvalue is '+parts);
            List<String> keyValue = pvalue.split('=');
            orgProperties.put(keyValue[0], keyValue[1]);
        }
        System.debug('orgProperties ' +orgProperties);
    }

    public String mySubString (String myString, Integer maxlen) {
        return myString == null ? '' : myString.substring(0, Math.min(myString.length(),maxlen)).trim();
    }

    public void homebrewUpsert(Contact theContact) {
        theContact.FirstName = mySubString(theContact.FirstName, 40);
        theContact.LastName = mySubString(theContact.LastName , 40);
        theContact.SUNet_ID__c = mySubString(theContact.SUNet_ID__c, 40);
        theContact.Email = mySubString(theContact.Email, 75);
        theContact.Phone = mySubString(theContact.Phone, 40);
        theContact.Department = mySubString(theContact.Department, 40);
        theContact.suaffiliation__c = mySubString(theContact.suaffiliation__c, 40);
        theContact.Rank__c = mySubString(theContact.Rank__c, 40);
        theContact.Stanford_Dept__c = mySubString(theContact.Stanford_Dept__c, 75);
        theContact.Alternate_Emails__c = mySubString(theContact.Alternate_Emails__c, 250);
        List<Contact> contactList = [SELECT Id, Email FROM Contact WHERE Email = :theContact.Email];
        if (contactList.size() > 0) {
            theContact.Id = contactList.get(0).Id;
            update theContact;
            return;
        }
        // not found as a primary email so check in the Alternate_Emails field
        String fuzzyEmail = '%' + theContact.Email + '%';
        contactList = [
                SELECT Id FROM Contact WHERE Alternate_Emails__c LIKE :fuzzyEmail ORDER BY Id ASC
        ];

        if (contactList.size() > 0) {
            System.debug('found alternate contact using fuzzyEmail ' + fuzzyEmail);
            theContact.Id = contactList.get(0).Id;
            update theContact;
            return;
        }

        // one last try - look for an exact match on name
        contactList = [SELECT Id, Name FROM Contact WHERE Name = :theContact.Name];
        if (contactList.size() > 0) {
            theContact.Id = contactList.get(0).Id;
            update theContact;
            return;
        }

        // ok we've done our due diligence, lets just let the default behavior take over
        upsert theContact;

    }

    private static String getDateAndTime() {
        //   e.g.    'On Jul 8, 2018, at 2:06 PM';
        Datetime myDatetime = Datetime.now();
        return 'On ' + myDatetime.format('MMM d, yyyy') + ' at ' + myDatetime.format('h:mm a');
    }

    public String removeTags(String message) {
        Pattern tagPattern = Pattern.compile(TAG_REGEX);
        Matcher myMatcher = tagPattern.matcher(message);
        while(myMatcher.find()) {
            String tagName = myMatcher.group(1).toLowerCase();
            if(VALID_TAGS.contains(tagName)) {
                message = message.replace(myMatcher.group(0), '');
            }
        }
        if (message.trim().equals('>')) {
            return '';
        }
        return message.trim();
    }

    /**
     * return all email addresses for the SF users in the named queue.
     *
     * @param queueName
     *
     * @return String[] all email addresses for the SF users in the named queue
     */
    public String[] getEmailByQueueName(String queueName) {
        return getEmailByUserIdSet(getUsersInQueueByName(queueName));
    }

    public String[] getEmailByQueueOrUserId(Id queueOrUserId) {
        Set<Id> userSet = new Set<Id>();
        userSet.add(queueOrUserId);
        String[] userEmail =  getEmailByUserIdSet(getUsersInQueueById( queueOrUserId));
        System.debug(' in getEmailByQueueOrUserId (line 690) ' + userEmail);
        if (userEmail.size() == 0) {
            // must be a queue rather than an actual user
            userEmail = getEmailByUserIdSet(userSet);
            System.debug(' in getEmailByQueueOrUserId  (line 694)' + userEmail);
        }
        return userEmail;
    }

    public String[] getEmailByUserIdSet( Set<Id> userIds) {
        List<String> supportTeamMembers = new List<String>();
        List<User> usrList = [SELECT Email FROM User WHERE Id IN :userIds];
        for(User usr : usrList) {
            supportTeamMembers.add(usr.Email);
        }
        System.debug('in getEmailByQueueIdSet, userIds is '+userIds+' supportTeamMembers is ' + supportTeamMembers);
        return supportTeamMembers;
    }

    public Set<Id> getUsersInQueueById(Id queueId) {
        //Set to return
        Set<Id> queueUsers = new Set<Id>();
        //Queue was passed by Name - get Id

        List<Group> groupIdList = [SELECT Id, Name FROM Group WHERE Type = 'Queue' AND Id = :queueId];
        //Continue only if an Id for a queue with the passed Name was found. Otherwise, return empty set.
        if( ! groupIdList.isEmpty()) {
            Id groupId = groupIdList.get(0).Id;

            //Create set and populate with user or group Ids that are queue members
            Set<Id> groupMemberIds = new Set<Id>();
            for(GroupMember mbr : [SELECT UserOrGroupId FROM GroupMember WHERE GroupId = :groupId]) {
                groupMemberIds.add(mbr.UserOrGroupId);
            }
            //Get all group members
            queueUsers = getGroupMembers(groupMemberIds);
        }
        System.debug('in getUsersInQueueById for ' + queueId + ' queueUsers is ' + queueUsers);
        return queueUsers;
    }

    public Set<Id> getUsersInQueueByName(String queueName) {
        //Set to return
        Set<Id> queueUsers = new Set<Id>();
        //Queue was passed by Name - get Id
        List<Group> groupIdList = [SELECT Id, Name FROM Group WHERE Type = 'Queue' AND Name = :queueName];
        //Continue only if an Id for a queue with the passed Name was found. Otherwise, return empty set.
        if( ! groupIdList.isEmpty()) {
            Id groupId = groupIdList.get(0).Id;

            //Create set and populate with user or group Ids that are queue members
            Set<Id> groupMemberIds = new Set<Id>();
            for(GroupMember mbr : [SELECT UserOrGroupId FROM GroupMember WHERE GroupId = :groupId]) {
                groupMemberIds.add(mbr.UserOrGroupId);
            }
            //Get all group members
            queueUsers = getGroupMembers(groupMemberIds);
        }
        System.debug('in getUsersInQueue for ' + queueName + ' queueUsers is ' + queueUsers);
        return queueUsers;
    }

    private Set<Id> getGroupMembers(Set<Id> idList) {
        //Add individual group members to userIds set.
        //Add public group members to groupIds set.
        Set<Id> userIds = new Set<Id>();
        Set<Id> groupIds = new Set<Id>();
        for(Id userOrGroupId : idList) {
            if(userOrGroupId.getSobjectType() == User.SObjectType) {
                userIds.add(userOrGroupId);
            }
            else {
                groupIds.add(userOrGroupId);
            }
        }

        //If there are public group members, get all the users in the public groups.
        //Note that public groups can themselves contain public group members.
        //This method calls itself recursively when passed a list containing one ore more group Ids,
        //so groups nested inside groups are handled.

        if( ! groupIds.isEmpty() ) {

            for(GroupMember grpMbr : [SELECT UserOrGroupId FROM GroupMember WHERE GroupId IN :groupIds]) {
                if(grpMbr.UserOrGroupId.getSobjectType() == User.SObjectType) {
                    //Id for user - add to user ids.
                    userIds.add(grpMbr.UserOrGroupId);
                }
                else {
                    //Id for group - do recursive call to get users in group
                    Set<Id> grpSet = new Set<Id>();
                    grpSet.add(grpMbr.UserOrGroupId);
                    userIds.addAll(getGroupMembers(grpSet));
                }
            }
        }
        return userIds;
    }

    public void trimCaseToFit() {
        theCase.SUnet_ID_case__c = mySubString(theCase.SUnet_ID_case__c, 49);
        theCase.Subject = mySubString(theCase.Subject, 254);
        theCase.Availability__c = mySubString(theCase.Availability__c, 3199);
        theCase.Description = mySubString(theCase.Description, 3199);
        theCase.IRB_Protocol__c = mySubString(theCase.IRB_Protocol__c, 49);
        theCase.PI_Name__c = mySubString(theCase.PI_Name__c, 49);
        theCase.Project_Record_ID__c = mySubString(theCase.Project_Record_ID__c, 19);
        theCase.Project_Department__c = mySubString(theCase.Project_Department__c , 99);
        theCase.REDCap_StudyName__c = mySubString(theCase.REDCap_StudyName__c, 239);
        theCase.Publication_Plans__c = mySubString(theCase.Publication_Plans__c, 49);
        theCase.CustomOrigin__c = mySubString(theCase.CustomOrigin__c , 49);
        theCase.SCI_Sponsor__c = mySubString(theCase.SCI_Sponsor__c , 49);
    }

    public Case getExistingCase(Messaging.InboundEmail email) {
        // Determine if there is an existing case by the contents of this email.
        // Step 1: look for a case number in the subject
        String vcn = parseValidCaseNumber(email.subject);
        Case theCase = null;
        if (vcn != '') {
            theCase = getCaseByCaseNumber(vcn);
        }		//found case number
        else {
            // Step 2: look for a case ThreadId
            String ref = parseThreadId(email.subject);
            if (ref == '') {ref = parseThreadId(email.htmlBody);}
            if (ref == '') {ref = parseThreadId(email.plainTextBody);}
            if (ref != '') {
                theCase = getCaseByThreadId(ref);
            }
        }			//found thread

        return theCase; // this will be null if the case was not found
    }

    public String parseValidCaseNumber (String content) {
        // Search for a case number in the content and check to see if it is valid
        // If so, return the the case Number - otherwise ''
        String sGetCaseNumber = '(CASE-\\d{6})';
        String result = regExMatchReturnGroup(content, sGetCaseNumber, 1);
        if (result=='') {
            return '';
        } else {
            if (getCaseByCaseNumber(result) == null) {
                return '';
            } else {
                return result;
            }
        }
    }

    //Do a regEx search and return a group
    public String regExMatchReturnGroup(String content, String regEx, Integer groupNumber) {
        if (content == null) return '';
        Matcher match = Pattern.compile(regEx).matcher(content);
        if (match.find()) {
            return match.group(groupNumber);
        } else {
            //system.debug('Unable to find regEx: [' + regEx + '] in content [' + content + '] so we are unable to return group [' + groupNumber +']');
            return '';
        }
    }

    public Case getCaseByCaseNumber (String caseNumber) {
        // Search for a case number in the content and then return the Case object
        // We found a match, lets see if it is valid
        List<Case> matchingCases = [SELECT Id, CaseNumber, Subject, Availability__c, Description, Status, OwnerId, Contact.Id, Contact.FirstName, Contact.LastName, Contact.Name, Contact.Email, reference__c, Owner.Alias, Owner.Name, Owner.Type, Active_Queue__c, Total_Labor__c, Project_Record_ID__c FROM Case WHERE CaseNumber=:caseNumber];
        if (matchingCases.size()==1) {
            Case c = matchingCases.get(0);
            System.debug('** Returning a preexisting case: ' + c.CaseNumber+ ' '+c.Contact);
            return c;
        } else {
            System.debug('** We were expecting a single valid case but got a size of: ' + matchingCases.size());
            return null;
        }
    }

    public String parseThreadId (String content) {
        // Search for a thread id from the content
        String sThreadFormat = '(ref:\\w+?\\.\\w+?:ref)';
        String result = regExMatchReturnGroup(content, sThreadFormat, 1);
        if (result=='') {
            // no match
            return '';
        } else {
            System.debug('** Found ThreadID Match:  ' + result);
            return result;
        }
    }

    public Case getCaseByThreadId (String ref) {
        String likeClause = '%' + ref + '%';
        List<Case> matchingCases = [SELECT  Id, CaseNumber, Subject, Availability__c, Description, Status, OwnerId, Contact.Id, Contact.FirstName, Contact.LastName, Contact.Name, Contact.Email, reference__c, Owner.Alias, Owner.Name, Owner.Type, Active_Queue__c, Total_Labor__c, Project_Record_ID__c  FROM Case WHERE reference__c LIKE :likeClause];
        if (matchingCases.size()==1) {
            Case c = matchingCases.get(0);
            System.debug('** Returning a preexisting case: ' + c.CaseNumber + ' from thread: ' + ref);
            return c;
        } else {
            return null;
        }
    }

    public Case getCaseByRedcapId (String redcapId) {
        List<Case> matchingCases = [SELECT  Id, CaseNumber, Subject, Availability__c, Description, Status, OwnerId, Contact.Id, Contact.FirstName, Contact.LastName, Contact.Name, Contact.Email, reference__c, Owner.Alias, Owner.Name, Owner.Type, Active_Queue__c, Total_Labor__c, Project_Record_ID__c  FROM Case WHERE Project_Record_ID__c = :redcapId];
        if (matchingCases.size()==1) {
            Case c = matchingCases.get(0);
            System.debug('** Returning a preexisting case: ' + c.CaseNumber + ' from Project_Record_ID__c: ' + redcapId);
            return c;
        } else {
            return null;
        }
    }

    /**
     * Produces a map of action tags to their supplied parameters
     *
     *
     * @param message
     *
     * @return
     */
    public Map<String, String> getTags(String message) {
        Map<String, String> returnMap = new Map<String, String>();
        Pattern tagPattern = Pattern.compile(TAG_REGEX);
        // if for example the action tag was @labor=3, then
        // myMatcher.group(0) is @labor=3
        // myMatcher.group(1) is labor
        // myMatcher.group(2) is 3
        Matcher myMatcher = tagPattern.matcher(message);
        while(myMatcher.find()) {
            String tagName = myMatcher.group(1).toLowerCase();
            if(VALID_TAGS.contains(tagName)) {
                String tagValue = myMatcher.group(2);
                returnMap.put(tagName, tagValue);
            }
        }
        return returnMap;
    }

    public String pareDownEmail(String content) {
        Pattern tagPattern = Pattern.compile(EMAIL_REGEX);
        Matcher myMatcher = tagPattern.matcher(content);
        if (myMatcher.find()) {
            System.debug('in pareDownEmail, extracted  ' + myMatcher.group(0).toLowerCase() + ' from ' + content);
            return myMatcher.group(0).toLowerCase();
        }
        return content;
    }

    @Future(Callout=true)
    private static void updateRedcap(String aCaseNumber, String aCaseStatus, String aCaseOwner, Boolean firstTime, String activeQueue, String recordIdStr) {

        /*
        created_on:
        case_number:
        status:
        owner:
        org:
        last_updated_on:
        ss: UQJ7NAL9HGAV2PKG9QT1NIM0SDH45Y
        record_id:
         */
        String queueString = 'RIC';
        if (activeQueue != null && activeQueue.startsWith('queuename=Research')) {
            queueString = 'Research IT';
        } else if (activeQueue != null && activeQueue.containsIgnoreCase('redcap')) {
            queueString = 'REDCap';
        }
        Http auth = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://redcap.stanford.edu/api/?type=module&prefix=srap&page=pages%2FsRAP_salesforce&NOAUTH');

        req.setMethod('POST');
        req.setHeader('Content-Type','x-www-form-urlencoded');
        req.setHeader('Accept','application/json');

        String body = '{"ss":"UQJ7NAL9HGAV2PKG9QT1NIM0SDH45Y","record_id":' + recordIdStr+
        ',"case_number":"'+aCaseNumber+'","status":"'+aCaseStatus+'","owner":"'+aCaseOwner+'","org":"'+queueString+'","salesforce_case_complete":2';
        if (firstTime) {
            body +=   ',"created_on":"' + getDateAndTime().substring(3) + '"';
        } else {
            body +=   ',"last_updated_on":"' + getDateAndTime().substring(3) + '"';
        }
        body +=   '}';
        req.setBody(body);
        System.debug('preparing to talk to REDCap, body is' + body);
        try {

            HttpResponse authresp = auth.send(req);
            if(authresp.getStatusCode() == 200)
            {
                System.debug('Authentication success!!! ' + authresp);
            }
            else {
                System.debug('Authentication failed!!! ' + authresp + authresp.getStatusCode());
            }

        } catch (Exception e) {
            System.debug(e.getMessage());
        }

    }
}