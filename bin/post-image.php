<?php

$file_name_with_full_path = $argv[1];
$target_url = 'http://uploads.im/api';
$cFile = curl_file_create($file_name_with_full_path);
$post = array('format' => 'json','file_contents'=> $cFile);
$curl = curl_init();
curl_setopt($curl, CURLOPT_URL,$target_url);
curl_setopt($curl, CURLOPT_POST,1);
curl_setopt($curl, CURLOPT_POSTFIELDS, $post);
curl_setopt($curl, CURLOPT_RETURNTRANSFER, TRUE);
$curl_response = json_decode(curl_exec($curl));
curl_close($curl);
print $curl_response->data->thumb_url;
