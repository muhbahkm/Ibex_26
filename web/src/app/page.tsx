import { redirect } from 'next/navigation';
import { auth } from '@/lib/auth/server';
import { getCurrentAppUser } from '@/lib/db/identity';

export const dynamic = 'force-dynamic';

export default async function HomePage() {
  const { data: session } = await auth.getSession();
  if (!session?.user) redirect('/auth/sign-in');

  const appUser = await getCurrentAppUser(session.user.id);

  return (
    <main className="workspace">
      <aside className="sidebar">
        <div className="brand"><span className="brand-mark small">B</span><div><strong>باحكم</strong><small>المساعد التشغيلي</small></div></div>
        <nav><button className="active">محادثة جديدة</button><button>العملاء</button><button>العمليات</button><button>الديون</button><button>التقارير</button></nav>
        <div className="user-card"><span>{session.user.name ?? session.user.email}</span><small>{appUser ? appUser.role : 'الحساب غير مرتبط'}</small></div>
      </aside>
      <section className="chat">
        <header><div><h1>كيف أساعدك في إدارة العمل؟</h1><p>{appUser ? `متصل بنشاط ${appUser.business_id.slice(0, 8)}…` : 'تم تسجيل الدخول، لكن يلزم ربط الحساب بمستخدم IBEX قبل تنفيذ العمليات المالية.'}</p></div><span className={appUser ? 'status ok' : 'status warn'}>{appUser ? 'جاهز' : 'بحاجة إلى ربط'}</span></header>
        <div className="conversation">
          <div className="welcome-card"><strong>ابدأ بأمر طبيعي</strong><p>مثال: بع كيلو سمرة SI للزبون العام بـ 20000 YER نقدًا.</p><p className="muted">في المرحلة التالية سيحوّل Agent الأمر إلى مسودة منظمة، ولن تُسجل أي حركة قبل اعتمادك.</p></div>
        </div>
        <div className="composer"><textarea placeholder="اكتب العملية أو السؤال هنا…" rows={2} disabled={!appUser} /><button disabled={!appUser}>إرسال</button></div>
      </section>
    </main>
  );
}
