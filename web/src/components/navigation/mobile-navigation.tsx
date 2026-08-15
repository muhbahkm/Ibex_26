'use client';

type Section = 'chat' | 'customers' | 'transactions' | 'debts' | 'reports';
type Props = { section: Section; onChange: (section: Section) => void };

const tabs: { id: Section; label: string }[] = [
  { id: 'chat', label: 'المحادثة' },
  { id: 'customers', label: 'العملاء' },
  { id: 'transactions', label: 'العمليات' },
  { id: 'debts', label: 'الديون' },
  { id: 'reports', label: 'التقارير' },
];

export function MobileNavigation({ section, onChange }: Props) {
  return <>
    <nav className="mobile-workspace-nav" aria-label="التنقل الرئيسي">
      {tabs.map((tab) => <button key={tab.id} className={section === tab.id ? 'active' : ''} onClick={() => onChange(tab.id)} type="button">{tab.label}</button>)}
    </nav>
    <style>{`
      .mobile-workspace-nav{display:none}
      @media(max-width:820px){
        .mobile-workspace-nav{display:grid;grid-template-columns:repeat(5,1fr);position:fixed;z-index:60;bottom:0;left:0;right:0;background:rgba(17,19,21,.96);backdrop-filter:blur(14px);padding:8px 8px max(8px,env(safe-area-inset-bottom));border-top:1px solid #2b2e31;gap:4px}
        .mobile-workspace-nav button{border:0;background:transparent;color:#aeb3b9;border-radius:10px;padding:10px 4px;font-size:11px;cursor:pointer;min-width:0}
        .mobile-workspace-nav button.active{background:#fff;color:#151719;font-weight:700}
        .operations-content{padding-bottom:92px!important}
        .conversation{padding-bottom:92px!important}
        .composer{margin-bottom:78px!important}
      }
    `}</style>
  </>;
}
