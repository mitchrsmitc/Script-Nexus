Connect-ExchangeOnline
$copy = Read-Host "Enter username to checked shared inboxes from"

Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited | Get-MailboxPermission -User $copy