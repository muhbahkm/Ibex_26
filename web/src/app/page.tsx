import { redirect } from 'next/navigation';
import { auth } from '@/lib/auth/server';
import { getCurrentAppUser } from '@/lib/db/identity';
import { ChatWorkspace } from '@/components/chat/chat-workspace';

export const dynamic = 'force-dynamic';

export default async function HomePage() {
  const { data: session } = await auth.getSession();
  if (!session?.user) redirect('/auth/sign-in');

  const appUser = await getCurrentAppUser(session.user.id);

  return (
    <ChatWorkspace
      displayName={session.user.name ?? session.user.email ?? 'مستخدم'}
      roleLabel={appUser?.role ?? 'الحساب غير مرتبط'}
      accountLinked={Boolean(appUser)}
      businessId={appUser?.business_id ?? ''}
      businessLabel={appUser ? `متصل بالنشاط ${appUser.business_id.slice(0, 8)}…` : ''}
    />
  );
}
