import nodemailer from 'nodemailer';

function createTransport() {
  const { SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS } = process.env;
  if (!SMTP_HOST || !SMTP_USER || !SMTP_PASS) return null;

  return nodemailer.createTransport({
    host: SMTP_HOST,
    port: Number(SMTP_PORT) || 587,
    secure: Number(SMTP_PORT) === 465,
    auth: { user: SMTP_USER, pass: SMTP_PASS },
  });
}

export async function sendPasswordResetEmail(email: string, otp: string): Promise<void> {
  const from = process.env.SMTP_FROM || process.env.SMTP_USER || 'noreply@vidme.app';
  const transport = createTransport();

  const subject = 'VidMe — your password reset code';
  const text = `Your VidMe password reset code is: ${otp}\n\nThis code expires in 15 minutes.\nIf you did not request this, ignore this email.`;
  const html = `
    <div style="font-family:sans-serif;max-width:480px;margin:0 auto">
      <h2 style="color:#1E88E5">VidMe Password Reset</h2>
      <p>Enter the code below in the app to reset your password.</p>
      <div style="font-size:36px;font-weight:bold;letter-spacing:8px;
                  background:#1a1a1a;color:#fff;padding:20px 32px;
                  border-radius:8px;display:inline-block;margin:16px 0">
        ${otp}
      </div>
      <p style="color:#666;font-size:13px">Expires in 15 minutes. If you did not request this, ignore this email.</p>
    </div>`;

  if (!transport) {
    // Dev fallback — print to console when SMTP is not configured
    console.log(`\n──────────────────────────────────`);
    console.log(`  PASSWORD RESET CODE for ${email}`);
    console.log(`  OTP: ${otp}`);
    console.log(`──────────────────────────────────\n`);
    return;
  }

  await transport.sendMail({ from, to: email, subject, text, html });
}
