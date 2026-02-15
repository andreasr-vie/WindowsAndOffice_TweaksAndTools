$mailboxes = Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails SharedMailbox

$data =@()
foreach($mailbox in $mailboxes){
If ((Get-EXOMailboxPermission $mailbox.Name | where {$_.IsInherited -eq $false -and $_.Deny -eq $false -and $_.AccessRights -eq "FullAccess"}) -eq $null){
if((Get-EXORecipientPermission $mailbox.Name -Trustee "NT AUTHORITY\SELF") -ne $null){
if((Get-EXORecipientPermission $mailbox.Name | where {$_.Trustee -ne "NT AUTHORITY\SELF"}) -eq $null){
$data+=$mailbox.Name
}
}
}
$data
}
