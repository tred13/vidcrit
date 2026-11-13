import { useState } from "react";

type Ev = { t: number; label: string; note: string };

const EVENTS: Ev[] = [
  { t: 0.0, label: "الماركر skit_t0", note: "يكتبه المود؛ يبدأ منه حساب الـ 10.9 ثانية" },
  { t: 2.4, label: "الدجاجة تضع TNT", note: "ظهور الـTNT مع غبار وشرارات الفتيل" },
  { t: 2.9, label: "القروي يلاحظ", note: "يدير رأسه نحو الـTNT" },
  { t: 4.2, label: "ارتجاف القروي", note: "الذعر يزداد حتى الانفجار" },
  { t: 5.42, label: "الانفجار", note: "mcl_explosions.explode بقوة 2.2 + هزّة كاميرا" },
  { t: 6.3, label: "الدجاجة تسقط على رأس القروي", note: "قوس قذف ثم هبوط عمودي على الرأس" },
  { t: 10.9, label: "نهاية الفيديو", note: "720×1280 بمعدل 30 إطار/ث" },
];

const STEPS = [
  ["01", "تثبيت المحرّك", "ppa:minetestdevs/stable مع رفض أي إصدار أقل من 5.10"],
  ["02", "تنزيل VoxeLibre", "المجلد mineclone2 إلى ~/.luanti/games/voxelibre"],
  ["03", "تجهيز العالم", "world.mt و map_meta.txt (ينتهي بـ [end_of_params]) ومود skit"],
  ["04", "Xvfb + openbox", "شاشة :99 بقياس 720×1280×24 ثم تشغيل luanti --go"],
  ["05", "التسجيل", "ffmpeg x11grab بـ 30 إطار/ث ثم قص 10.9 ث بعد الماركر بدقة"],
  ["06", "المخرجات", "artifact يحوي mp4 وgif وstills وlog"],
];

const FACTS = [
  ["المسافة", "6.3 – 6.9 بلوك"],
  ["الممثلان", "داخل ±1.2 بلوك من المحور"],
  ["رأس القروي", "في الثلث الأعلى من الإطار"],
  ["أرضية المسرح", "في أسفل الإطار"],
  ["مجال الرؤية العمودي", "42° (مع مضاعف المحرّك 1.4)"],
  ["قوة الانفجار", "2.2 (الحد الأقصى المسموح 2.5)"],
];

export default function App() {
  const [active, setActive] = useState(4);
  const ev = EVENTS[active];

  return (
    <div dir="rtl" className="min-h-screen bg-slate-950 text-slate-100">
      <div className="mx-auto max-w-5xl px-5 py-12">
        <header className="mb-12 space-y-4">
          <span className="inline-block rounded-full border border-amber-400/40 bg-amber-400/10 px-3 py-1 text-xs text-amber-300">
            التصيير يتم في GitHub Actions فقط
          </span>
          <h1 className="text-4xl font-bold tracking-tight md:text-5xl">vidcrit</h1>
          <p className="max-w-2xl text-lg leading-8 text-slate-400">
            خط تصيير لسكيت كوميدي صامت بين قروي ودجاجة داخل عالم VoxeLibre حقيقي على Luanti،
            بمخرج عمودي 9:16 جاهز لـ Shorts وReels وTikTok.
          </p>
        </header>

        <section className="mb-12 grid gap-6 md:grid-cols-[1fr_280px]">
          <div className="rounded-2xl border border-slate-800 bg-slate-900/60 p-6">
            <h2 className="mb-5 text-xl font-semibold">الجدول الزمني</h2>
            <div className="relative mb-6 h-2 rounded-full bg-slate-800">
              {EVENTS.map((e, i) => (
                <button
                  key={e.t}
                  onClick={() => setActive(i)}
                  aria-label={e.label}
                  style={{ right: `${(e.t / 10.9) * 100}%` }}
                  className={`absolute top-1/2 h-4 w-4 -translate-y-1/2 translate-x-1/2 rounded-full border-2 transition ${
                    i === active
                      ? "scale-125 border-amber-300 bg-amber-400"
                      : "border-slate-600 bg-slate-900 hover:border-slate-400"
                  }`}
                />
              ))}
            </div>
            <div className="min-h-[88px] rounded-xl bg-slate-950/70 p-4">
              <div className="mb-1 font-mono text-sm text-amber-300">t = {ev.t.toFixed(2)} s</div>
              <div className="text-lg font-medium">{ev.label}</div>
              <div className="text-sm text-slate-400">{ev.note}</div>
            </div>
            <p className="mt-3 text-xs text-slate-500">
              كل حدث يُسجَّل في skit_events.log بالزمن الفعلي والمتوقع (المقبول ±0.2 ث).
            </p>
          </div>

          <div
            aria-hidden
            className="relative mx-auto aspect-[9/16] w-full max-w-[220px] overflow-hidden rounded-2xl border border-slate-700 bg-gradient-to-b from-sky-400 via-sky-300 to-emerald-500"
          >
            <div className="absolute inset-x-0 top-[17%] h-[16%] bg-red-700/90" />
            <div className="absolute inset-x-0 top-[17%] h-[3%] bg-yellow-400" />
            <div className="absolute inset-x-[-10%] bottom-[8%] h-[22%] bg-amber-800" />
            <div className="absolute inset-x-[-10%] bottom-[8%] h-[5%] bg-amber-600" />
            <div className="absolute bottom-[30%] left-[22%] h-[24%] w-[14%] rounded-sm bg-emerald-800" />
            <div
              className={`absolute bottom-[30%] right-[26%] h-[6%] w-[9%] rounded-sm bg-white transition-all duration-500 ${
                active >= 5 ? "!bottom-[54%] !left-[22%] !right-auto" : ""
              }`}
            />
            <div
              className={`absolute bottom-[30%] left-[44%] h-[8%] w-[12%] rounded-sm bg-red-500 transition ${
                active === 1 || active === 2 || active === 3 ? "opacity-100" : "opacity-0"
              }`}
            />
            <div
              className={`absolute bottom-[34%] left-[34%] h-[30%] w-[32%] rounded-full bg-orange-400/80 blur-md transition ${
                active === 4 ? "opacity-100" : "opacity-0"
              }`}
            />
          </div>
        </section>

        <section className="mb-12">
          <h2 className="mb-5 text-xl font-semibold">خطوات الـ CI</h2>
          <div className="grid gap-3 md:grid-cols-2">
            {STEPS.map(([n, title, text]) => (
              <div key={n} className="flex gap-4 rounded-xl border border-slate-800 bg-slate-900/60 p-4">
                <div className="font-mono text-2xl text-slate-600">{n}</div>
                <div>
                  <div className="font-medium">{title}</div>
                  <div className="text-sm text-slate-400">{text}</div>
                </div>
              </div>
            ))}
          </div>
        </section>

        <section className="mb-12 rounded-2xl border border-slate-800 bg-slate-900/60 p-6">
          <h2 className="mb-5 text-xl font-semibold">الكاميرا</h2>
          <p className="mb-5 text-sm leading-7 text-slate-400">
            مفاتيح كاميرا (keyframes) على المحور الأمامي مع نقطة نظر واحدة على المحور نفسه. اصطلاح
            الدوران لـ set_look_* يُقاس مرة واحدة عند البدء (قراءة get_look_dir) ثم يُخزَّن ولا
            يُكرَّر في كل إطار.
          </p>
          <dl className="grid gap-3 sm:grid-cols-2 md:grid-cols-3">
            {FACTS.map(([k, v]) => (
              <div key={k} className="rounded-xl bg-slate-950/70 p-4">
                <dt className="text-xs text-slate-500">{k}</dt>
                <dd className="mt-1 font-medium">{v}</dd>
              </div>
            ))}
          </dl>
        </section>

        <footer className="text-sm text-slate-500">
          شغّل الـ workflow باسم <span className="font-mono text-slate-300">render-skit</span> من تبويب
          Actions ثم نزّل artifact باسم <span className="font-mono text-slate-300">vidcrit-skit</span>.
        </footer>
      </div>
    </div>
  );
}
