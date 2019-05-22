<?PHP


//form variables
$phoneNumber 	= trim($_GET['number']);
$provider 		= trim($_GET['provider']);
$bib 			= trim($_GET['bib']);

$item 			= $_GET['item']; //parse the item
$itemArray 		= explode("|", $item);
$location 		= trim($itemArray[0]);

$title = html_entity_decode(trim($_GET['title']));

//strip strange characters not handled by Safari from location
$location 		= preg_replace('/[^A-Za-z0-9\-_\.\s]/', "", $location);
$location 		= trim($location);

$callNumber 	= trim($itemArray[1]);
$item 			= "\nLoc: ".$location."\nCall: ".$callNumber;
//echo "document.write('Debug: ".$location." ".$callNumber."');";


//verify that the call number and location are listed on the page for extra security
//if(!strstr($catalogItemPage, $callNumber) || !strstr($catalogItemPage, $location)){
//	echo "alert('There was a problem. Message not sent!');";
//	exit;
//}

//defined variables. Set the from address and subject as desired
$fromAddress 	= 'NoReply@searchmobius.org';
$subject 		= "Library Catalog";

$providers = array(	'cingular' 	=> '@mobile.mycingular.com',
             		'tmobile' 	=> '@tmomail.net',
             		'virgin' 	=> '@vmobl.com',
             		'sprint' 	=> '@messaging.sprintpcs.com',
             		'nextel' 	=> '@messaging.nextel.com',
             		'verizon'	=> '@vtext.com',
			'northwest' => '@mynwmcell.com',
			'cricket'	=> '@mms.mycricket.com',
			'qwest'		=> '@qwestmp.com',
			'att' 	    => '@txt.att.net',
			'uscellular' => '@email.uscc.net',
			'projectfi' => '@msg.fi.google.com',
			'republicwireless' => '@text.republicwireless.com');
				

//remove any non-numeric characters from the phone number
$number = preg_replace('/[^\d]/', '', $phoneNumber);

if(strlen($phoneNumber) == 10) { //does the phone have 10 digits

	if($providers[$provider]){ //is the provider valid
		
		//Format the email.
		$toAddress = $number.$providers[$provider];
		$body = "$item \nTitle: $title";

		//send the email
		mail($toAddress, $subject, $body, "From: $fromAddress");
		
		echo "alert('Message sent!');";
		echo "clearsms();";
		exit;
	}
}

echo "alert('Problem found. Message not sent!');";

?>
