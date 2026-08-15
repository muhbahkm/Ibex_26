'use client';

import Link from 'next/link';
import { FormEvent, useState } from 'react';
import { useRouter } from 'next/navigation';
import { authClient } from '@/lib/auth/client';

export function SignInForm() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setError(null);

    const data = new FormData(event.currentTarget);
    const email = String(data.get('email') ?? '');
    const password = String(data.get('password') ?? '');

    const result = await authClient.signIn.email({ email, password });
    if (result.error) {
      setError('تعذر تسجيل الدخول. تحقق من البيانات وحاول مرة أخرى.');
      setPending(false);
      return;
    }

    router.replace('/');
    router.refresh();
  }

  return (
    <form className="auth-card" onSubmit={submit}>
      <div className="brand-mark">B</div>
      <h1>باحكم للعسل</h1>
      <p>الدخول إلى المساعد التشغيلي الذكي</p>
      <label>البريد الإلكتروني<input name="email" type="email" autoComplete="email" required /></label>
      <label>كلمة المرور<input name="password" type="password" autoComplete="current-password" required /></label>
      {error && <div className="error-box">{error}</div>}
      <button disabled={pending} type="submit">{pending ? 'جارٍ الدخول…' : 'تسجيل الدخول'}</button>
      <p className="auth-switch">ليس لديك حساب؟ <Link href="/auth/sign-up">إنشاء حساب</Link></p>
    </form>
  );
}
