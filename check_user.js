
const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'https://wpspozyarpczjlkrowjt.supabase.co';
const supabaseServiceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Indwc3BvenlhcnBjempsa3Jvd2p0Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MTQ5ODQxNywiZXhwIjoyMDg3MDc0NDE3fQ.K08DBz16nFDQ6b_YLwyWktX42hWVHS-OD0fQ2zVYbxo';

const supabase = createClient(supabaseUrl, supabaseServiceKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  }
});

async function checkUser() {
  const email = 'carlosalegria@me.com';
  console.log(`Checking if user ${email} exists...`);
  
  const { data: { users }, error } = await supabase.auth.admin.listUsers();
  
  if (error) {
    console.error('Error listing users:', error);
    return;
  }

  const user = users.find(u => u.email === email);
  
  if (user) {
    console.log('User found:', user.id);
  } else {
    console.log('User NOT found. This confirms the database reset or account not registered.');
    console.log('Current users in DB:', users.length);
  }
}

checkUser();
