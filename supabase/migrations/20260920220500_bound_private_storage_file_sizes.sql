update storage.buckets
set file_size_limit = case id
  when 'profile-photos' then 10485760
  when 'attendance-evidence' then 15728640
  when 'qualification-certificates' then 20971520
  when 'communication-albums' then 20971520
  when 'worker-documents' then 52428800
  when 'chat-attachments' then 52428800
  else file_size_limit
end
where id in (
  'profile-photos',
  'attendance-evidence',
  'qualification-certificates',
  'communication-albums',
  'worker-documents',
  'chat-attachments'
);
