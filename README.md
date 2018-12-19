# salesforce-email-handler
## Custom APEX classes for handling new case creation from the Research Portal for RIT &amp; RIC
### Salesforce Email Handler
User’s and Administrator’s Guide
User's Guide
REDCap and Research IT customers wishing to open a new case should use the web form at https://redcap.stanford.edu/plugins/gethelp/rit.php.  The submit handler (submit_v2.php) for this form sends a structured email to rit-support@stanford.edu, the email address associated with the Salesforce email handler, specifying the Research IT intake queue.

Research Informatics Center customers will use https://redcap.stanford.edu/plugins/gethelp/ric.php, which we should perhaps mask with a vanity URL such as https://richelp.med.stanford.edu/ to avoid any implicit connection with REDCap.  The submit handler for this form will also send a structured email to Salesforce, specifying the RIC intake queue. The email associated with the new handler is ric-support@stanford.edu .

The email informatics-consultation@lists.stanford.edu will remain associated with the old intake process.

The redcap-help email will also continue to function as it did before.

To open a new case using the new process, the web forms must be used. If a customer sends an email with neither ref tag nor case number, they are sent a polite message redirecting them to the web intake process.  In the case where either a ref tag associated with the case or the case number are present in an email, the handler associates newly supplied information in the email to the specified case. Notification emails are sent both to the customer and to the consultant (or the specified Salesforce queue) when a new case is opened, but only to the other party in the correspondence when a follow-up email is received.

Both consultants and customers wishing to interact with Salesforce send email to the address associated with the handler, e.g. <rit-support@stanford.edu> or <ric-support@stanford.edu>. 

You simply reply to these emails; all text above the ==== line are appended to the case as a comment which triggers an email to the customer.  Consultants can also optionally include action tags to trigger the following operations:

#### @OPEN 
<optional comments>
This opens a case and assigns it to the person who sent the reply.  Any comments will be sent to the other users (submittor) associated with the ticket. The comment here is not part of the OPEN action tag, but rather is any case comment that gets associated to the case in the comment feed.

#### @PRIVATE @HIDE @HIDDEN [comment]
These three synonymous tags all specify that the comment should not be emailed to the customer. If you do not want the comment to be sent back as an email to the person who submitted the ticket, then add the @PRIVATE/HIDE/HIDDEN tag.

#### @ASSIGN=<SF handle> <optional comments>
This assigns the case to the designated consultant OR queue. If the handle is not recognized the original consultant is notified of the problem. All comments are by default public, so if your comment is addressed to the new owner and should not be routed to the customer, you need to add the @HIDE/HIDDEN/PRIVATE tag

#### @CLOSE  [optional comments]
This closes the case and notifies the consultant that the action succeeded. If a comment is present, it also notifies the customer with the text of the comment. The handler will not auto-notify on close, so it is up to the consultant to add whatever wording they feel is appropriate to notify the customer that they consider this case to be resolved.
#### @LABOR=# [optional comment]
This adds the supplied number to the labor field. If a comment is present, it also notifies the customer with the text of the comment unless the @HIDE tag is also present

### Test Scenario
Open a new case by completing https://redcap.stanford.edu/plugins/gethelp/ric.php in the name of an email address you control e.g. your private gmail account
A new case will be created and all users on the Research Informatics queue will be notified.
Log into GMail and reply to the message (e.g. This is urgent!). Again, everyone on the queue should see your response
Now switch back to your Stanford email and reply to the notification you received as a member of the queue. You can reply with @open or @assign or even just reply to the customer without taking any action
Once you open a case, further correspondence will only be routed to you

If you email rit-support@stanford.edu without a case reference, you should get an error message directing you to the web intake form.

### Backward Compatibility 
The existing informaticsconsultation@lists email address will continue to work as before unless this email is converted to redirect to the handler rather than the existing handler. Both systems share these behaviors:
Emails referencing a case add a comment to the case and generate a notification to the other party
When new cases are opened the appropriate queue of Salesforce users is notified
When new cases have been in the queue for more than 8 working hours the queue is again notified
When a case is assigned to a consultant, the new case owner is notified via email

### Migration Plan
The cutover to the new system will involve all new email accounts, so the old system will continue to work until we decide to take it offline by redirecting it to send to one of the new accounts.

Public web references to the old intake form include 
https://med.stanford.edu/dbds/service/dcc/scirdb.html
http://med.stanford.edu/researchit/resources/grant-writing-resources.html
https://med.stanford.edu/researchit/infrastructure/clinical-data-warehouse/cohort-tool-guide.html
https://med.stanford.edu/content/dam/sm/researchit/Content/STARR-Data-Dictionary.pdf
http://med.stanford.edu/ric.html 
http://med.stanford.edu/ric/contact.html
http://med.stanford.edu/researchit.html
http://med.stanford.edu/researchit/contact-us.html

### Migration tasks
Obtain internal sign-off on testing of the new handler in the sandbox (done!)
Update the forwarding address for ric-support@stanford.edu to forward to production SF rather than test (done!)
Configure the handler in production and conduct some final smoke tests (done!)
Go Live: Notify the website owners for the URLs listed above of the need to update the help URL.  RIC sites should update to https://redcap.stanford.edu/plugins/gethelp/ric.php

## Administrator’s Guide
### Email Templates
The wording of most outbound emails is managed using templates. In Setup, search on “Email Template”.  There are default versions of each message for shared use in cases where the customer intent of the inbound email can’t be inferred eg. from which email handler they used, as well as customized version named with suitable suffixes.  For example the template used when a customer sends an email with no recognizable case reference is called NACK_CUSTOMER_SEND_TO_WEB, and the Research Informatics Center version is called NACK_CUSTOMER_SEND_TO_WEB_RIC.

### Apex Code
The Salesforce email handler consists of two classes
SMEmailHandler - the top level handler class containing the business logic controlling who is notified under which conditions
SMScheduledJobArchiveClosedCase - a scheduled job that changes closed cases to Archived after some period of time.

If you are interested in learning how to make modifications to these files, the Trailhead tutorials are a good introduction https://trailhead.salesforce.com/en

To find where the Apex handler is associated with inbound email, search "Email Services" in Setup

The version 1.0 web form that generates data for new cases is hosted on REDCap. There are two forms, https://redcap.stanford.edu/plugins/gethelp/rit.php and https://redcap.stanford.edu/plugins/gethelp/ric.php. These are slightly different - the RIC version includes a question about SCI membership, and the Research IT version asks about REDCap. They each have a hidden form field specifying which email address the resulting JSon / email is sent to.  

The 2nd phase of this is to replace the help form with the project-based portal for PIs. This will likely take a few months. Lee Ann is actively working on this. 

The version 1.0 system produces JSON that corresponds to the Salesforce objects in question when the user fills out the new project form, and a regular email with a case reference in it when the user fills out a question associated with an existing project.


The queues named in rit.php and ric.php both must exist and have email addresses associated with them. To find queues, search on “Queue” in Setup and click on Queues under Users. RIT1 is currently the hardcoded default queue - 1. is this the right name and 2. is there a better place to put this info than in the class

To find where the email templates are stored, search on “Email Template” in Setup and select “Classic Email Templates”

The email templates currently support the following references

{subject}
The subject line of the inbound email
{case}
The case number of the newly created or referenced case
{customerName}
The full name of the customer e.g. Susan Weber
{owner}
The name of the owner of the case
{ref}
The Salesforce ref tag
{description}
The original case description
{comment}
The newly added comment
{url}
The Salesforce URL for the case

The current email templates are

QUEUE_NEW_CASE_NOTIFICATION
A new ticket was created by {customerName}. 
Please reply above the separator. 

You can take ownership of this case by replying to this email with @open. Need help? Reply with @info

----------------- 

{description} 

{url}
{ref}
CUSTOMER_ACK_INCOMING_REQUEST
Dear {customerName}, 

Thank you for contacting us regarding {subject}; your inquiry has been recorded in our case tracking system as {case}. Please include this case number in all future correspondence with us on this topic. 

We are currently experiencing a roughly three week backlog due to high demand for our services. If your inquiry is time-sensitive, please reply to this email with "Urgent" in your message. 

Cheers, 
-{team name} 

{ref}
CONSULTANT_CASE_ALREADY_OPEN
This case has already been opened by {owner}. Your response has been added as a private comment to the case.
CUSTOMER_CASE_ARCHIVED_NOTIFICATION
<note the URL and team name - these will be customized depending on whether the owner of the case was named in a RIC queue or a RIT queue>
Dear {customerName}, 

Your request regarding "{subject}"' has been closed. 

To reach us for assistance, please open a new case using the request form at {helpurl}. 

We look forward to hearing from you, 

-{team name}
NOTIFY_CASE_COMMENT
{comment}
CONSULTANT_INFO
You can take ownership of a case by replying the system-generated email using the action tag:   @open

Tags are case insensitive, so either @open or @OPEN will work

All tags consider additional text in a message to be a case comment, which will be conveyed to the customer.  Multiple tags can be used in a single response.  Tags are stripped from the response prior to forwarding to the customer.

If you do not wish the customer to see your comment, you can respond internally by adding tags @HIDDEN, @PRIVATE or @HIDE. 

Other useful tags include:
@LABOR=n    <optional comment>

@ASSIGN=salesforceAlias  <optional comment>

@CLOSE <optional comment>


New fields
Contact has new text field Affiliation to hold the value from the intake form that specifies whether this person is faculty or staff, and if faculty, UTL v non-tenured.  This may be useful later for reporting to see who our customers are.

Case has a new text field OriginQueue that stores the queue specified on case creation. This value will be used to determine which team name to sign outbound notifications on new case creation and on rejection of an email associated with an archived case

Case might benefit from a new Contact field to keep the information of the person submitting the form, in case this differs from the information filled out in the text fields, as it will when someone is submitting the form on behalf of someone else

### System Components
Shared iMap email accounts hosted by Stanford
To administer / update, go to accounts.stanford.edu, click on Manage, then click on Email Forwarding
redcap-help@stanford.edu administered by Susan: https://accounts.stanford.edu/manage/shared/redcap-help
In Setup->Email Services->SMEmailService, forwards to the “REDCap Help” SF user
ric-support@stanford.edu administered by Susan: https://accounts.stanford.edu/manage/shared/ric-support
In Setup->Email Services->SMEmailService, forwards to the “RIC Support” SF user 
rit-support@stanford.edu administered by Andy: https://accounts.stanford.edu/manage/shared/rit-support
In Setup->Email Services->SMEmailService, forwards to the “Research IT Support” SF user
SMEmailService - written in ApEx, this is a custom Salesforce Email Service. To configure, log into Salesforce, click on Setup, and browse to Email Service. To review the source code, log into Salesforce, click on Developer Console, click Edit and filter on SM to locate the SMEmailService class.
Salesforce Queues
To configure, search on Queue in Setup. The new system uses the same three queues used by the current system. Queues determine who is notified on new case creation - the queue name is supplied in the JSon, then looked up and explicitly referenced in the handler when sending out emails.
REDCap projects
Susan’s v 1.0 prototype uses two projects, https://redcap.stanford.edu/redcap_v8.6.5/index.php?pid=13941 to track the project and https://redcap.stanford.edu/redcap_v8.6.5/index.php?pid=13942 to record requests coming in from the web form. The URL for the request forms are https://redcap.stanford.edu/plugins/gethelp/rit.php and https://redcap.stanford.edu/plugins/gethelp/ric.php  
Lee Ann’s v 2.0 uses a single project with repeating forms and an External Module for the UI rather than a plugin

When a user submits a request using https://redcap.stanford.edu/plugins/gethelp/rit.php or https://redcap.stanford.edu/plugins/gethelp/ric.php, hidden form fields specify which intake queue to send the request to.  The email handler parses the incoming message content and takes appropriate action, but the logic of which email address is used to send the reply is set by the user associated with the handler in the configuration screen.  So for example when debugging you need to change the associated user to one you have a login password for, outbound emails will come from that user rather than from the pseudo-user “Research IT Support”.

Release Process
To release from test to production, you first need to create a test case with at least 75% coverage.

Here is a useful guide on how to use the Ant deployment tool: https://developer.salesforce.com/docs/atlas.en-us.214.0.daas.meta/daas/meta_development.htm  

If you use Ant, the setup is as follows
Create a new subdirectory in salesforce_ant_43.0 next to sample. I called mine “smeh”
cp sample/build.xml smeh
cp sample/build.properties smeh
mkdir smeh/codepkg
mkdir smeh/codepkg/classes
cp ~/whatever/SMEmailService* smeh/codepkg/classes
vi build.properties: set sf.username and sf.password. sf.password is a concatenation of your password and the 25 digit security token. To generate the security token, log into prod SF as the user you refer to in sf.username, search on security token in setup and reset it.  Also set sf.serverurl = https://login.salesforce.com
cp sample/codepkg/package.xml smeh/codepkg
vi smeh/codepkg/package.xml - it should look like the following
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>SMEmailService</members>
        <members>SMEmailServiceTest</members>
        <name>ApexClass</name>
    </types>
    <version>43.0</version>
</Package>

This process does not succeed for some reason with scheduled job classes (it complains of 0 code coverage even when packaged w/ 80% coverage test class) so at this time production does not have a scheduled job to archive closed cases

