'use client';

import Link from 'next/link';
import { FormEvent, useState } from 'react';
import { useRouter } from 'next/navigation';
import { authClient } from '@/lib/auth/client';

export function SignUpForm() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setError(null);

    const data = new FormData(event.currentTarget);
    const name = String(data.get('name') ?? '').trim();
    const email = String(data.get('email') ?? '').trim();
    const password = String(data.get('password') ?? '');

    if (password.length < 8) {
      setError('كلمة المرور يجب أن تكون 8 أحرف على الأقل.');
      setPending(false);
      return;
    }

    const result = await authClient.signUp.email({ name, email, password });
    if (result.error) {
      setError('تعذر إنشاء الحساب. تحقق من البيانات أو جرّب بريدًا آخر.');
      setPending(false);
      return;
    }

    router.replace('/');
    router.refresh();
  }

  return (
    <form className="auth-card" onSubmit={submit}>
      <div className="brand-mark">B</div>
      <h1>إنشاء حساب</h1>
      <p>أنشئ هوية دخول جديدة. لن تحصل على صلاحيات مالية حتى يتم ربط الحساب بمستخدم IBEX.</p>
      <label>الاسم<input name="name" type="text" autoComplete="name" required /></label>
      <label>البريد الإلكتروني<input name="email" type="email" autoComplete="email" required /></label>
      <label>كلمة المرور<input name="password" type="password" autoComplete="new-password" minLength={8} required /></label>
      {error && <div className="error-box">{error}</div>}
      <button disabled={pending} type="submit">{pending ? 'جارٍ إنشاء الحساب…' : 'إنشاء الحساب'}</button>
      <p className="auth-switch">لديك حساب؟ <Link href="/auth/sign-in">تسجيل الدخول</Link></p>
    </form>
  );
}
