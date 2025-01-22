<?php
//redirect to config.php if it seems like thats what we really want
if (empty($_SERVER['PATH_INFO'])) {
	header("Location: /admin/config.php");
} else {
	header("Location: api.php");	
}

?>
