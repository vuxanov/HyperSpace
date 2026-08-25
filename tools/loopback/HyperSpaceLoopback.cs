// HyperSpace WASAPI capture helper.
// Sends 48 kHz stereo int16 packets to 127.0.0.1 (Godot PacketPeerUDP).
//
// Modes:
//   --mode loopback   default render endpoint, loopback capture (what Windows plays)
//   --mode mic        default capture endpoint in WASAPI RAW mode, which bypasses the
//                     Realtek/Lenovo AISPEECHAPO "Voice Focus" APO. That APO treats music
//                     as background noise, so the processed mic stream only hears speech.
//   --mode miccheck   diagnostic: measure peak/RMS + 8-band spectrum, print, exit.
//                     Use --raw 0 to measure the processed (APO) stream for comparison.
//
// Compile:
//   %WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /optimize+ /out:HyperSpaceLoopback.exe HyperSpaceLoopback.cs
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Microsoft.Win32;

internal static class Program
{
	public const int DefaultPort = 27123;
	public const int OutRate = 48000;
	const uint LoopbackFlag = 0x00020000;
	const uint SilentFlag = 0x2;
	const int ERender = 0;
	const int ECapture = 1;
	const int EMultimedia = 1;
	const int DeviceStateAll = 0xF;
	const int ClsCtxAll = 23;

	static readonly Guid IidAudioClient = new Guid("1CB9AD4C-DBFA-4C32-B178-C2F568A703B2");
	static readonly Guid IidAudioClient2 = new Guid("726778CD-F60A-4EDA-82DE-E47610CD78AA");
	static readonly Guid IidCaptureClient = new Guid("C8ADBD64-E71E-48A0-A4DE-185C395CD317");
	static readonly Guid IeeeFloat = new Guid("00000003-0000-0010-8000-00AA00389B71");
	static readonly Guid Pcm = new Guid("00000001-0000-0010-8000-00AA00389B71");

	// PKEY_AudioEndpoint_Disable_SysFx — 1 disables the endpoint effects (APO) chain.
	static readonly Guid EndpointFmtId = new Guid("1DA5D803-D492-4EDD-8C23-E0C0FFEE7F0E");
	const int PidDisableSysFx = 5;
	const uint StreamOptionsRaw = 0x1;
	const int AudioCategoryOther = 0;
	const int StgmWrite = 0x1;

	static string _mode = "loopback";
	static bool HighPassCheck;

	static string StatusPath
	{
		get { return Path.Combine(Path.GetTempPath(), "hyperspace_" + StemForMode + ".status"); }
	}

	static string PidPath
	{
		get { return Path.Combine(Path.GetTempPath(), "hyperspace_" + StemForMode + ".pid"); }
	}

	static string StemForMode
	{
		get { return _mode == "mic" ? "rawmic" : "loopback"; }
	}

	static int Main(string[] args)
	{
		int port = DefaultPort;
		double seconds = 6.0;
		bool raw = true;
		bool trySysFx = false;
		for (int i = 0; i < args.Length; i++)
		{
			if (args[i] == "--sysfx" && i + 1 < args.Length)
				trySysFx = args[i + 1] != "0";
			if (args[i] == "--hp" && i + 1 < args.Length)
				HighPassCheck = args[i + 1] != "0";
			if (args[i] == "--port" && i + 1 < args.Length)
				int.TryParse(args[i + 1], out port);
			else if (args[i] == "--mode" && i + 1 < args.Length)
				_mode = args[i + 1].ToLowerInvariant();
			else if (args[i] == "--seconds" && i + 1 < args.Length)
				double.TryParse(args[i + 1], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out seconds);
			else if (args[i] == "--raw" && i + 1 < args.Length)
				raw = args[i + 1] != "0";
		}

		if (_mode == "miccheck")
		{
			try { return RunMicCheck(seconds, raw, trySysFx); }
			catch (Exception ex)
			{
				Console.WriteLine("error " + ex.Message);
				return 1;
			}
		}

		KillPreviousInstance();
		WritePid();
		DisableCommunicationsDucking();

		if (_mode == "mic")
		{
			string sysfx = "";
			try
			{
				RunMicCapture(port, raw, trySysFx, out sysfx);
				return 0;
			}
			catch (Exception ex)
			{
				WriteStatus("error", ex.Message, "", "", sysfx);
				return 1;
			}
		}

		string stereoMix = TryEnableStereoMix();
		WriteStatus("starting", "opening WASAPI loopback", "", stereoMix, "");

		try
		{
			RunLoopback(port, stereoMix);
			return 0;
		}
		catch (Exception ex)
		{
			WriteStatus("error", ex.Message, "", stereoMix, "");
			return 1;
		}
	}

	static void KillPreviousInstance()
	{
		// Kill only the previous instance of THIS mode. Loopback + raw mic run together.
		try
		{
			if (!File.Exists(PidPath))
				return;
			int old;
			if (!int.TryParse(File.ReadAllText(PidPath).Trim(), out old) || old <= 0 || old == ProcessId())
				return;
			var proc = System.Diagnostics.Process.GetProcessById(old);
			if (proc != null && proc.ProcessName == "HyperSpaceLoopback")
				proc.Kill();
		}
		catch { }
	}

	static void WritePid()
	{
		try { File.WriteAllText(PidPath, ProcessId().ToString()); }
		catch { }
	}

	static int ProcessId()
	{
		return System.Diagnostics.Process.GetCurrentProcess().Id;
	}

	static void DisableCommunicationsDucking()
	{
		try
		{
			Registry.SetValue(
				@"HKEY_CURRENT_USER\Software\Microsoft\Multimedia\Audio",
				"UserDuckingPreference",
				3,
				RegistryValueKind.DWord);
		}
		catch { }
	}

	static string TryEnableStereoMix()
	{
		string note = "none";
		try
		{
			var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
			IMMDeviceCollection coll;
			int hr = enumerator.EnumAudioEndpoints(ECapture, DeviceStateAll, out coll);
			if (hr != 0 || coll == null)
				return "enum-failed";
			uint count;
			coll.GetCount(out count);
			for (uint i = 0; i < count; i++)
			{
				IMMDevice dev;
				if (coll.Item(i, out dev) != 0 || dev == null)
					continue;
				string name = FriendlyName(dev);
				string id = DeviceId(dev);
				if (string.IsNullOrEmpty(name) || string.IsNullOrEmpty(id))
					continue;
				string lower = name.ToLowerInvariant();
				if (!(lower.Contains("stereo mix") || lower.Contains("what u hear") || lower.Contains("wave out mix")))
					continue;
				uint state;
				dev.GetState(out state);
				note = name + " state=" + state;
				if ((state & 2) != 0 || state == 0)
				{
					int vis = PolicySetVisible(id, true);
					note += " visibility-hr=0x" + vis.ToString("X8");
				}
			}
		}
		catch (Exception ex)
		{
			note = "enable-failed " + ex.Message;
		}
		return note;
	}

	static int PolicySetVisible(string deviceId, bool visible)
	{
		try
		{
			var cfg = (IPolicyConfig)new PolicyConfigClient();
			return cfg.SetEndpointVisibility(deviceId, visible ? 1 : 0);
		}
		catch
		{
			try
			{
				var cfg = (IPolicyConfigVista)new PolicyConfigVistaClient();
				return cfg.SetEndpointVisibility(deviceId, visible ? 1 : 0);
			}
			catch
			{
				return unchecked((int)0x80004005);
			}
		}
	}

	static void RunLoopback(int port, string stereoMix)
	{
		var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
		IMMDevice device;
		int hr = enumerator.GetDefaultAudioEndpoint(ERender, EMultimedia, out device);
		if (hr != 0 || device == null)
			throw new Exception("no default render device hr=0x" + hr.ToString("X8"));

		string renderName = FriendlyName(device);
		object clientObj;
		Guid clientIid = IidAudioClient;
		hr = device.Activate(ref clientIid, ClsCtxAll, IntPtr.Zero, out clientObj);
		if (hr != 0)
			throw new Exception("Activate IAudioClient hr=0x" + hr.ToString("X8"));
		var client = (IAudioClient)clientObj;

		IntPtr mixPtr;
		hr = client.GetMixFormat(out mixPtr);
		if (hr != 0 || mixPtr == IntPtr.Zero)
			throw new Exception("GetMixFormat hr=0x" + hr.ToString("X8"));

		WaveFormat fmt = WaveFormat.FromPointer(mixPtr);
		const long bufferHns = 2000000; // 200 ms
		hr = client.Initialize(0, LoopbackFlag, bufferHns, 0, mixPtr, IntPtr.Zero);
		CoTaskMemFree(mixPtr);
		if (hr != 0)
			throw new Exception("Initialize loopback hr=0x" + hr.ToString("X8") + " " + fmt);

		object capObj;
		Guid capIid = IidCaptureClient;
		hr = client.GetService(ref capIid, out capObj);
		if (hr != 0)
			throw new Exception("GetService capture hr=0x" + hr.ToString("X8"));
		var capture = (IAudioCaptureClient)capObj;

		hr = client.Start();
		if (hr != 0)
			throw new Exception("Start hr=0x" + hr.ToString("X8"));

		var udp = new UdpClient();
		udp.Connect(IPAddress.Loopback, port);

		var resampler = new Resampler(fmt.SampleRate, OutRate);
		WriteStatus("ok", "loopback " + fmt, renderName, stereoMix);

		byte[] scratch = new byte[0];
		float[] stereo = new float[0];
		long packets = 0;
		float peakSend = 0f;
		int silentMs = 0;
		try
		{
			while (true)
			{
				uint next;
				hr = capture.GetNextPacketSize(out next);
				if (hr != 0)
					throw new Exception("GetNextPacketSize hr=0x" + hr.ToString("X8"));
				if (next == 0)
				{
					silentMs += 8;
					if (silentMs >= 40)
					{
						SendPacket(udp, new float[512]);
						silentMs = 0;
						packets++;
					}
					Thread.Sleep(8);
					continue;
				}
				silentMs = 0;

				IntPtr data;
				uint frames;
				uint flags;
				ulong pos, qpc;
				hr = capture.GetBuffer(out data, out frames, out flags, out pos, out qpc);
				if (hr != 0)
					throw new Exception("GetBuffer hr=0x" + hr.ToString("X8"));

				int bytes = (int)(frames * fmt.BlockAlign);
				if (scratch.Length < bytes)
					scratch = new byte[bytes];
				if (bytes > 0 && data != IntPtr.Zero)
					Marshal.Copy(data, scratch, 0, bytes);
				capture.ReleaseBuffer(frames);

				bool silent = (flags & SilentFlag) != 0 || data == IntPtr.Zero;
				int needed = (int)frames * 2;
				if (stereo.Length < needed)
					stereo = new float[needed];
				if (silent)
					Array.Clear(stereo, 0, needed);
				else
					DecodeToStereo(scratch, (int)frames, fmt, stereo);

				float[] outBuf = resampler.Push(stereo, (int)frames);
				if (outBuf.Length > 0)
				{
					for (int i = 0; i < outBuf.Length; i++)
					{
						float a = Math.Abs(outBuf[i]);
						if (a > peakSend) peakSend = a;
					}
					SendPacket(udp, outBuf);
					packets++;
					if (packets == 1 || packets % 80 == 0)
					{
						WriteStatus("ok", "loopback " + fmt + " packets=" + packets + " peak=" + peakSend.ToString("0.0000"), renderName, stereoMix);
						peakSend = 0f;
					}
				}
			}
		}
		finally
		{
			try { client.Stop(); }
			catch { }
			udp.Close();
		}
	}

	/// Opens the default capture (mic) endpoint. When raw is true the stream is put in
	/// WASAPI raw processing mode, which bypasses the endpoint's APO chain — on this
	/// machine that is the Realtek/Lenovo AISPEECHAPO that strips music.
	static IAudioCaptureClient OpenMicCapture(bool raw, bool trySysFx, out IAudioClient client, out WaveFormat fmt, out string deviceName, out string modeNote, out string sysFxNote)
	{
		var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
		IMMDevice device;
		int hr = enumerator.GetDefaultAudioEndpoint(ECapture, 0 /* eConsole */, out device);
		if (hr != 0 || device == null)
			throw new Exception("no default capture device hr=0x" + hr.ToString("X8"));

		deviceName = FriendlyName(device);
		// Committing endpoint properties raises a device-change notification that
		// invalidates freshly created audio clients, and unelevated writes do not
		// persist anyway. Raw mode is the real bypass, so only try this on request.
		sysFxNote = trySysFx ? TryDisableSysFx(device) : "not-attempted";
		if (trySysFx)
			Thread.Sleep(600);

		object clientObj;
		modeNote = "processed";
		IAudioClient2 client2 = null;
		if (raw)
		{
			Guid iid2 = IidAudioClient2;
			if (device.Activate(ref iid2, ClsCtxAll, IntPtr.Zero, out clientObj) == 0 && clientObj != null)
				client2 = clientObj as IAudioClient2;
		}

		if (client2 != null)
		{
			var props = new AudioClientProperties
			{
				cbSize = (uint)Marshal.SizeOf(typeof(AudioClientProperties)),
				bIsOffload = 0,
				eCategory = AudioCategoryOther,
				Options = StreamOptionsRaw,
			};
			int rawHr = client2.SetClientProperties(ref props);
			if (rawHr == 0)
			{
				modeNote = "raw";
			}
			else
			{
				// Win8-era struct has no Options field. Retry without it so at least the
				// category is applied, then report that raw was refused.
				var legacy = props;
				legacy.cbSize = 12;
				legacy.Options = 0;
				client2.SetClientProperties(ref legacy);
				modeNote = "processed(raw-hr=0x" + rawHr.ToString("X8") + ")";
			}
			client = (IAudioClient)client2;
		}
		else
		{
			Guid iid = IidAudioClient;
			hr = device.Activate(ref iid, ClsCtxAll, IntPtr.Zero, out clientObj);
			if (hr != 0 || clientObj == null)
				throw new Exception("Activate IAudioClient hr=0x" + hr.ToString("X8"));
			client = (IAudioClient)clientObj;
			if (raw)
				modeNote = "processed(no-IAudioClient2)";
		}

		IntPtr mixPtr;
		hr = client.GetMixFormat(out mixPtr);
		if (hr != 0 || mixPtr == IntPtr.Zero)
			throw new Exception("GetMixFormat hr=0x" + hr.ToString("X8"));
		fmt = WaveFormat.FromPointer(mixPtr);

		const long bufferHns = 2000000; // 200 ms
		hr = client.Initialize(0, 0, bufferHns, 0, mixPtr, IntPtr.Zero);
		CoTaskMemFree(mixPtr);
		if (hr != 0)
			throw new Exception("Initialize capture hr=0x" + hr.ToString("X8") + " " + fmt + " mode=" + modeNote);

		object capObj;
		Guid capIid = IidCaptureClient;
		hr = client.GetService(ref capIid, out capObj);
		if (hr != 0)
			throw new Exception("GetService capture hr=0x" + hr.ToString("X8"));

		hr = client.Start();
		if (hr != 0)
			throw new Exception("Start hr=0x" + hr.ToString("X8"));
		return (IAudioCaptureClient)capObj;
	}

	/// Best-effort, never elevated. Writing endpoint FxProperties normally needs admin,
	/// so report the HRESULT instead of pretending it worked.
	static string TryDisableSysFx(IMMDevice device)
	{
		try
		{
			IPropertyStore store;
			int hr = device.OpenPropertyStore(StgmWrite, out store);
			if (hr != 0 || store == null)
				return "open-hr=0x" + hr.ToString("X8");
			var key = new PropertyKey(EndpointFmtId, PidDisableSysFx);
			var pv = new PropVariant { vt = 19 /* VT_UI4 */, ptr = new IntPtr(1) };
			int setHr = store.SetValue(ref key, ref pv);
			int commitHr = setHr == 0 ? store.Commit() : setHr;
			if (commitHr != 0)
				return "denied hr=0x" + commitHr.ToString("X8");
			// Commit returns S_OK unelevated but silently drops the write. Read it back
			// through a fresh store so the status never claims a change that did not land.
			IPropertyStore verify;
			if (device.OpenPropertyStore(0, out verify) == 0 && verify != null)
			{
				PropVariant got;
				if (verify.GetValue(ref key, out got) == 0 && got.vt == 19 && got.ptr.ToInt64() == 1)
					return "disabled";
			}
			return "not-persisted (needs elevation)";
		}
		catch (Exception ex)
		{
			return "failed " + ex.Message;
		}
	}

	static void RunMicCapture(int port, bool raw, bool trySysFx, out string sysFxNote)
	{
		IAudioClient client;
		WaveFormat fmt;
		string deviceName, modeNote;
		var capture = OpenMicCapture(raw, trySysFx, out client, out fmt, out deviceName, out modeNote, out sysFxNote);

		var udp = new UdpClient();
		udp.Connect(IPAddress.Loopback, port);
		var resampler = new Resampler(fmt.SampleRate, OutRate);
		// Raw mode has no noise suppression, and fan/desk rumble dominates everything below
		// ~150 Hz — measured, it swings several-fold on its own, which is enough to look
		// like signal to any noise-floor estimator downstream. Laptop speakers cannot put
		// out useful energy down there anyway, so cut it before anything measures level.
		var hp = new HighPass(150.0, fmt.SampleRate);
		WriteStatus("ok", "mic " + fmt, deviceName, "", sysFxNote, modeNote);

		byte[] scratch = new byte[0];
		float[] stereo = new float[0];
		long packets = 0;
		float peakSend = 0f;
		int silentMs = 0;
		try
		{
			while (true)
			{
				uint next;
				int hr = capture.GetNextPacketSize(out next);
				if (hr != 0)
					throw new Exception("GetNextPacketSize hr=0x" + hr.ToString("X8"));
				if (next == 0)
				{
					silentMs += 8;
					if (silentMs >= 40)
					{
						SendPacket(udp, new float[512]);
						silentMs = 0;
						packets++;
					}
					Thread.Sleep(8);
					continue;
				}
				silentMs = 0;

				IntPtr data;
				uint frames, flags;
				ulong pos, qpc;
				hr = capture.GetBuffer(out data, out frames, out flags, out pos, out qpc);
				if (hr != 0)
					throw new Exception("GetBuffer hr=0x" + hr.ToString("X8"));

				int bytes = (int)(frames * fmt.BlockAlign);
				if (scratch.Length < bytes)
					scratch = new byte[bytes];
				if (bytes > 0 && data != IntPtr.Zero)
					Marshal.Copy(data, scratch, 0, bytes);
				capture.ReleaseBuffer(frames);

				bool silent = (flags & SilentFlag) != 0 || data == IntPtr.Zero;
				int needed = (int)frames * 2;
				if (stereo.Length < needed)
					stereo = new float[needed];
				if (silent)
					Array.Clear(stereo, 0, needed);
				else
				{
					DecodeToStereo(scratch, (int)frames, fmt, stereo);
					hp.Process(stereo, (int)frames);
				}

				float[] outBuf = resampler.Push(stereo, (int)frames);
				if (outBuf.Length > 0)
				{
					for (int i = 0; i < outBuf.Length; i++)
					{
						float a = Math.Abs(outBuf[i]);
						if (a > peakSend) peakSend = a;
					}
					SendPacket(udp, outBuf);
					packets++;
					if (packets == 1 || packets % 80 == 0)
					{
						WriteStatus("ok", "mic " + fmt + " packets=" + packets + " peak=" + peakSend.ToString("0.00000"), deviceName, "", sysFxNote, modeNote);
						peakSend = 0f;
					}
				}
			}
		}
		finally
		{
			try { client.Stop(); }
			catch { }
			udp.Close();
		}
	}

	/// Diagnostic: capture for a few seconds and print level + 8-band spectrum so the
	/// processed (APO) stream and the raw stream can be compared with real numbers.
	static int RunMicCheck(double seconds, bool raw, bool trySysFx)
	{
		IAudioClient client;
		WaveFormat fmt;
		string deviceName, modeNote, sysFxNote;
		var capture = OpenMicCapture(raw, trySysFx, out client, out fmt, out deviceName, out modeNote, out sysFxNote);

		Console.WriteLine("device=" + deviceName);
		Console.WriteLine("format=" + fmt);
		Console.WriteLine("requested_raw=" + (raw ? "1" : "0"));
		Console.WriteLine("mode=" + modeNote);
		Console.WriteLine("sysfx=" + sysFxNote);
		Console.WriteLine("highpass=" + (HighPassCheck ? "80Hz" : "off"));

		var hp = HighPassCheck ? new HighPass(80.0, fmt.SampleRate) : null;
		int rate = fmt.SampleRate;
		const int FftSize = 4096;
		var mono = new float[FftSize];
		int monoFill = 0;
		var bandAcc = new double[8];
		int bandFrames = 0;
		double peak = 0.0, sumSq = 0.0;
		long total = 0;
		byte[] scratch = new byte[0];
		float[] stereo = new float[0];
		var sw = System.Diagnostics.Stopwatch.StartNew();
		try
		{
			while (sw.Elapsed.TotalSeconds < seconds)
			{
				uint next;
				if (capture.GetNextPacketSize(out next) != 0)
					break;
				if (next == 0)
				{
					Thread.Sleep(5);
					continue;
				}
				IntPtr data;
				uint frames, flags;
				ulong pos, qpc;
				if (capture.GetBuffer(out data, out frames, out flags, out pos, out qpc) != 0)
					break;
				int bytes = (int)(frames * fmt.BlockAlign);
				if (scratch.Length < bytes)
					scratch = new byte[bytes];
				if (bytes > 0 && data != IntPtr.Zero)
					Marshal.Copy(data, scratch, 0, bytes);
				capture.ReleaseBuffer(frames);
				bool silent = (flags & SilentFlag) != 0 || data == IntPtr.Zero;
				int needed = (int)frames * 2;
				if (stereo.Length < needed)
					stereo = new float[needed];
				if (silent)
					Array.Clear(stereo, 0, needed);
				else
				{
					DecodeToStereo(scratch, (int)frames, fmt, stereo);
					if (hp != null)
						hp.Process(stereo, (int)frames);
				}

				for (int f = 0; f < frames; f++)
				{
					float s = (stereo[f * 2] + stereo[f * 2 + 1]) * 0.5f;
					double a = Math.Abs(s);
					if (a > peak) peak = a;
					sumSq += (double)s * s;
					total++;
					mono[monoFill++] = s;
					if (monoFill == FftSize)
					{
						AccumulateBands(mono, rate, bandAcc);
						bandFrames++;
						monoFill = 0;
					}
				}
			}
		}
		finally
		{
			try { client.Stop(); }
			catch { }
		}

		double rms = total > 0 ? Math.Sqrt(sumSq / total) : 0.0;
		Console.WriteLine("seconds=" + sw.Elapsed.TotalSeconds.ToString("0.00"));
		Console.WriteLine("peak=" + peak.ToString("0.000000"));
		Console.WriteLine("rms=" + rms.ToString("0.000000"));
		var names = new[] { "31-63", "63-125", "125-250", "250-500", "500-1k", "1k-2k", "2k-4k", "4k-16k" };
		for (int b = 0; b < 8; b++)
		{
			double v = bandFrames > 0 ? bandAcc[b] / bandFrames : 0.0;
			Console.WriteLine("band_" + names[b] + "=" + v.ToString("0.0000000"));
		}
		return 0;
	}

	static readonly double[] BandEdgesHz = { 31.0, 63.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 16000.0 };

	static void AccumulateBands(float[] mono, int rate, double[] bandAcc)
	{
		int n = mono.Length;
		var re = new double[n];
		var im = new double[n];
		for (int i = 0; i < n; i++)
		{
			// Hann window.
			double w = 0.5 - 0.5 * Math.Cos(2.0 * Math.PI * i / (n - 1));
			re[i] = mono[i] * w;
		}
		Fft(re, im);
		double binHz = (double)rate / n;
		for (int b = 0; b < 8; b++)
		{
			int lo = (int)Math.Max(1, Math.Floor(BandEdgesHz[b] / binHz));
			int hi = (int)Math.Min(n / 2 - 1, Math.Ceiling(BandEdgesHz[b + 1] / binHz));
			double sum = 0.0;
			int count = 0;
			for (int k = lo; k <= hi; k++)
			{
				sum += Math.Sqrt(re[k] * re[k] + im[k] * im[k]) * 2.0 / n;
				count++;
			}
			if (count > 0)
				bandAcc[b] += sum / count;
		}
	}

	static void Fft(double[] re, double[] im)
	{
		int n = re.Length;
		for (int i = 1, j = 0; i < n; i++)
		{
			int bit = n >> 1;
			for (; (j & bit) != 0; bit >>= 1)
				j ^= bit;
			j ^= bit;
			if (i < j)
			{
				double tr = re[i]; re[i] = re[j]; re[j] = tr;
				double ti = im[i]; im[i] = im[j]; im[j] = ti;
			}
		}
		for (int len = 2; len <= n; len <<= 1)
		{
			double ang = -2.0 * Math.PI / len;
			double wr = Math.Cos(ang), wi = Math.Sin(ang);
			for (int i = 0; i < n; i += len)
			{
				double cr = 1.0, ci = 0.0;
				for (int k = 0; k < len / 2; k++)
				{
					int a = i + k, b = i + k + len / 2;
					double xr = re[b] * cr - im[b] * ci;
					double xi = re[b] * ci + im[b] * cr;
					re[b] = re[a] - xr;
					im[b] = im[a] - xi;
					re[a] += xr;
					im[a] += xi;
					double ncr = cr * wr - ci * wi;
					ci = cr * wi + ci * wr;
					cr = ncr;
				}
			}
		}
	}

	static void DecodeToStereo(byte[] src, int frames, WaveFormat fmt, float[] dest)
	{
		int ch = fmt.Channels;
		bool isFloat = fmt.IsFloat;
		int bits = fmt.BitsPerSample;
		int block = fmt.BlockAlign;
		for (int f = 0; f < frames; f++)
		{
			int off = f * block;
			float l = 0f, r = 0f;
			if (isFloat && bits == 32)
			{
				l = BitConverter.ToSingle(src, off);
				r = ch > 1 ? BitConverter.ToSingle(src, off + 4) : l;
			}
			else if (isFloat && bits == 64)
			{
				l = (float)BitConverter.ToDouble(src, off);
				r = ch > 1 ? (float)BitConverter.ToDouble(src, off + 8) : l;
			}
			else if (bits == 16)
			{
				l = BitConverter.ToInt16(src, off) / 32768f;
				r = ch > 1 ? BitConverter.ToInt16(src, off + 2) / 32768f : l;
			}
			else if (bits == 24)
			{
				l = Read24(src, off);
				r = ch > 1 ? Read24(src, off + 3) : l;
			}
			else if (bits == 32)
			{
				l = BitConverter.ToInt32(src, off) / 2147483648f;
				r = ch > 1 ? BitConverter.ToInt32(src, off + 4) / 2147483648f : l;
			}
			if (ch > 2)
			{
				for (int c = 2; c < ch; c++)
				{
					float s = 0f;
					int co = off + c * (bits / 8);
					if (isFloat && bits == 32)
						s = BitConverter.ToSingle(src, co);
					else if (bits == 16)
						s = BitConverter.ToInt16(src, co) / 32768f;
					l += s * 0.2f;
					r += s * 0.2f;
				}
			}
			dest[f * 2] = Clamp(l);
			dest[f * 2 + 1] = Clamp(r);
		}
	}

	static float Read24(byte[] src, int off)
	{
		int v = src[off] | (src[off + 1] << 8) | (src[off + 2] << 16);
		if ((v & 0x800000) != 0)
			v |= unchecked((int)0xFF000000);
		return v / 8388608f;
	}

	static float Clamp(float v)
	{
		if (v > 1f) return 1f;
		if (v < -1f) return -1f;
		return v;
	}

	static DateTime _firstSendFailure = DateTime.MinValue;
	static SocketError _lastSendError;

	/// A connected UDP socket reports ICMP port-unreachable as a send error, so this is how
	/// the helper notices its Godot process is gone and exits instead of lingering and
	/// double-streaming into the next run. Judged on wall-clock, not a failure count: a
	/// receiver that is merely busy can refuse a burst of packets without being gone.
	static void SendOrExit(UdpClient udp, byte[] pkt)
	{
		try
		{
			udp.Send(pkt, pkt.Length);
			_firstSendFailure = DateTime.MinValue;
		}
		catch (SocketException ex)
		{
			_lastSendError = ex.SocketErrorCode;
			if (_firstSendFailure == DateTime.MinValue)
				_firstSendFailure = DateTime.UtcNow;
			else if ((DateTime.UtcNow - _firstSendFailure).TotalSeconds > 5.0)
			{
				WriteStatus("error", "receiver gone (" + _lastSendError + ")", "", "");
				Environment.Exit(0);
			}
		}
	}

	static void SendPacket(UdpClient udp, float[] interleaved)
	{
		int frames = interleaved.Length / 2;
		int max = 1024;
		int offset = 0;
		while (offset < frames)
		{
			int n = Math.Min(max, frames - offset);
			var pkt = new byte[12 + n * 4];
			pkt[0] = (byte)'H';
			pkt[1] = (byte)'S';
			pkt[2] = (byte)'L';
			pkt[3] = (byte)'B';
			WriteU32(pkt, 4, (uint)OutRate);
			WriteU16(pkt, 8, 2);
			WriteU16(pkt, 10, (ushort)n);
			int src = offset * 2;
			int dst = 12;
			for (int i = 0; i < n * 2; i++)
			{
				int s = (int)(interleaved[src + i] * 32767f);
				if (s > 32767) s = 32767;
				if (s < -32768) s = -32768;
				pkt[dst] = (byte)s;
				pkt[dst + 1] = (byte)(s >> 8);
				dst += 2;
			}
			SendOrExit(udp, pkt);
			offset += n;
		}
	}

	static void WriteU32(byte[] b, int o, uint v)
	{
		b[o] = (byte)v;
		b[o + 1] = (byte)(v >> 8);
		b[o + 2] = (byte)(v >> 16);
		b[o + 3] = (byte)(v >> 24);
	}

	static void WriteU16(byte[] b, int o, ushort v)
	{
		b[o] = (byte)v;
		b[o + 1] = (byte)(v >> 8);
	}

	static void WriteStatus(string state, string message, string device, string stereoMix, string sysFx = "", string mode = "")
	{
		try
		{
			var sb = new StringBuilder();
			sb.Append("state=").AppendLine(state);
			sb.Append("message=").AppendLine(message ?? "");
			sb.Append("device=").AppendLine(device ?? "");
			sb.Append("stereo_mix=").AppendLine(stereoMix ?? "");
			sb.Append("sysfx=").AppendLine(sysFx ?? "");
			sb.Append("capture_mode=").AppendLine(mode ?? "");
			sb.Append("pid=").AppendLine(ProcessId().ToString());
			File.WriteAllText(StatusPath, sb.ToString());
		}
		catch { }
	}

	static string FriendlyName(IMMDevice dev)
	{
		try
		{
			IPropertyStore store;
			if (dev.OpenPropertyStore(0, out store) != 0 || store == null)
				return "";
			var key = new PropertyKey(new Guid("A45C254E-DF1C-4EFD-8020-67D146A850E0"), 14);
			PropVariant pv;
			if (store.GetValue(ref key, out pv) != 0)
				return "";
			try
			{
				if (pv.vt == 31 && pv.ptr != IntPtr.Zero)
					return Marshal.PtrToStringUni(pv.ptr) ?? "";
			}
			finally
			{
				PropVariantClear(ref pv);
			}
		}
		catch { }
		return "";
	}

	static string DeviceId(IMMDevice dev)
	{
		IntPtr p;
		if (dev.GetId(out p) != 0 || p == IntPtr.Zero)
			return "";
		try { return Marshal.PtrToStringUni(p) ?? ""; }
		finally { CoTaskMemFree(p); }
	}

	[DllImport("ole32.dll")]
	static extern void CoTaskMemFree(IntPtr p);

	[DllImport("ole32.dll")]
	static extern int PropVariantClear(ref PropVariant pvar);
}

/// Second-order Butterworth high-pass, run per channel on interleaved stereo.
internal sealed class HighPass
{
	readonly double _a0, _a1, _a2, _b1, _b2;
	double _lx1, _lx2, _ly1, _ly2;
	double _rx1, _rx2, _ry1, _ry2;

	public HighPass(double cutoffHz, int sampleRate)
	{
		double w = Math.Tan(Math.PI * cutoffHz / Math.Max(sampleRate, 8000));
		double norm = 1.0 / (1.0 + Math.Sqrt(2.0) * w + w * w);
		_a0 = norm;
		_a1 = -2.0 * norm;
		_a2 = norm;
		_b1 = 2.0 * (w * w - 1.0) * norm;
		_b2 = (1.0 - Math.Sqrt(2.0) * w + w * w) * norm;
	}

	public void Process(float[] stereo, int frames)
	{
		for (int f = 0; f < frames; f++)
		{
			int i = f * 2;
			double x = stereo[i];
			double y = _a0 * x + _a1 * _lx1 + _a2 * _lx2 - _b1 * _ly1 - _b2 * _ly2;
			_lx2 = _lx1; _lx1 = x; _ly2 = _ly1; _ly1 = y;
			stereo[i] = (float)y;

			x = stereo[i + 1];
			y = _a0 * x + _a1 * _rx1 + _a2 * _rx2 - _b1 * _ry1 - _b2 * _ry2;
			_rx2 = _rx1; _rx1 = x; _ry2 = _ry1; _ry1 = y;
			stereo[i + 1] = (float)y;
		}
	}
}

internal sealed class Resampler
{
	readonly int _inRate;
	readonly int _outRate;
	double _pos;
	float _prevL, _prevR;
	bool _havePrev;
	float[] _out = new float[0];

	public Resampler(int inRate, int outRate)
	{
		_inRate = inRate < 8000 ? 48000 : inRate;
		_outRate = outRate;
	}

	public float[] Push(float[] stereo, int frames)
	{
		if (_inRate == _outRate)
		{
			var copy = new float[frames * 2];
			Array.Copy(stereo, copy, copy.Length);
			return copy;
		}
		int guess = (int)((long)frames * _outRate / _inRate) + 8;
		if (_out.Length < guess * 2)
			_out = new float[guess * 2];
		int written = 0;
		double step = (double)_inRate / _outRate;
		for (int i = 0; i < frames; i++)
		{
			float l = stereo[i * 2];
			float r = stereo[i * 2 + 1];
			if (!_havePrev)
			{
				_prevL = l;
				_prevR = r;
				_havePrev = true;
				continue;
			}
			while (_pos < 1.0)
			{
				float t = (float)_pos;
				_out[written * 2] = _prevL + (l - _prevL) * t;
				_out[written * 2 + 1] = _prevR + (r - _prevR) * t;
				written++;
				if (written * 2 >= _out.Length)
				{
					var bigger = new float[_out.Length * 2];
					Array.Copy(_out, bigger, _out.Length);
					_out = bigger;
				}
				_pos += step;
			}
			_pos -= 1.0;
			_prevL = l;
			_prevR = r;
		}
		var result = new float[written * 2];
		Array.Copy(_out, result, result.Length);
		return result;
	}
}

internal struct WaveFormat
{
	public int Channels;
	public int SampleRate;
	public int BitsPerSample;
	public int BlockAlign;
	public bool IsFloat;

	public static WaveFormat FromPointer(IntPtr p)
	{
		ushort tag = (ushort)Marshal.ReadInt16(p, 0);
		ushort ch = (ushort)Marshal.ReadInt16(p, 2);
		int rate = Marshal.ReadInt32(p, 4);
		ushort align = (ushort)Marshal.ReadInt16(p, 12);
		ushort bits = (ushort)Marshal.ReadInt16(p, 14);
		ushort cb = (ushort)Marshal.ReadInt16(p, 16);
		bool isFloat = tag == 3;
		if (tag == 0xFFFE && cb >= 22)
		{
			var sub = new Guid(
				Marshal.ReadInt32(p, 24),
				(short)Marshal.ReadInt16(p, 28),
				(short)Marshal.ReadInt16(p, 30),
				Marshal.ReadByte(p, 32), Marshal.ReadByte(p, 33),
				Marshal.ReadByte(p, 34), Marshal.ReadByte(p, 35),
				Marshal.ReadByte(p, 36), Marshal.ReadByte(p, 37),
				Marshal.ReadByte(p, 38), Marshal.ReadByte(p, 39));
			isFloat = sub == new Guid("00000003-0000-0010-8000-00AA00389B71");
		}
		return new WaveFormat
		{
			Channels = ch,
			SampleRate = rate,
			BitsPerSample = bits,
			BlockAlign = align,
			IsFloat = isFloat
		};
	}

	public override string ToString()
	{
		return SampleRate + "Hz " + Channels + "ch " + BitsPerSample + "bit " + (IsFloat ? "float" : "pcm");
	}
}

[StructLayout(LayoutKind.Sequential)]
internal struct PropertyKey
{
	public Guid fmtid;
	public int pid;
	public PropertyKey(Guid f, int p) { fmtid = f; pid = p; }
}

[StructLayout(LayoutKind.Sequential)]
internal struct PropVariant
{
	public ushort vt;
	public ushort w1, w2, w3;
	public IntPtr ptr;
	public IntPtr pad;
}

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
internal class MMDeviceEnumerator { }

[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMMDeviceEnumerator
{
	[PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
	[PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
	[PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
	[PreserveSig] int RegisterEndpointNotificationCallback(IntPtr client);
	[PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr client);
}

[ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387CEC"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMMDeviceCollection
{
	[PreserveSig] int GetCount(out uint count);
	[PreserveSig] int Item(uint index, out IMMDevice device);
}

[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMMDevice
{
	[PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
	[PreserveSig] int OpenPropertyStore(int access, out IPropertyStore store);
	[PreserveSig] int GetId(out IntPtr id);
	[PreserveSig] int GetState(out uint state);
}

[ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IPropertyStore
{
	[PreserveSig] int GetCount(out uint count);
	[PreserveSig] int GetAt(uint i, out PropertyKey key);
	[PreserveSig] int GetValue(ref PropertyKey key, out PropVariant pv);
	[PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant pv);
	[PreserveSig] int Commit();
}

[ComImport, Guid("1CB9AD4C-DBFA-4C32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IAudioClient
{
	[PreserveSig] int Initialize(int shareMode, uint streamFlags, long bufferDuration, long periodicity, IntPtr format, IntPtr session);
	[PreserveSig] int GetBufferSize(out uint frames);
	[PreserveSig] int GetStreamLatency(out long latency);
	[PreserveSig] int GetCurrentPadding(out uint padding);
	[PreserveSig] int IsFormatSupported(int shareMode, IntPtr format, out IntPtr closest);
	[PreserveSig] int GetMixFormat(out IntPtr format);
	[PreserveSig] int GetDevicePeriod(out long def, out long min);
	[PreserveSig] int Start();
	[PreserveSig] int Stop();
	[PreserveSig] int Reset();
	[PreserveSig] int SetEventHandle(IntPtr handle);
	[PreserveSig] int GetService(ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
}

[StructLayout(LayoutKind.Sequential)]
internal struct AudioClientProperties
{
	public uint cbSize;
	public int bIsOffload;
	public int eCategory;
	public uint Options;
}

/// IAudioClient2 adds SetClientProperties, which is the only supported way to ask
/// WASAPI for raw processing mode (APO bypass) on a capture stream.
[ComImport, Guid("726778CD-F60A-4EDA-82DE-E47610CD78AA"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IAudioClient2
{
	[PreserveSig] int Initialize(int shareMode, uint streamFlags, long bufferDuration, long periodicity, IntPtr format, IntPtr session);
	[PreserveSig] int GetBufferSize(out uint frames);
	[PreserveSig] int GetStreamLatency(out long latency);
	[PreserveSig] int GetCurrentPadding(out uint padding);
	[PreserveSig] int IsFormatSupported(int shareMode, IntPtr format, out IntPtr closest);
	[PreserveSig] int GetMixFormat(out IntPtr format);
	[PreserveSig] int GetDevicePeriod(out long def, out long min);
	[PreserveSig] int Start();
	[PreserveSig] int Stop();
	[PreserveSig] int Reset();
	[PreserveSig] int SetEventHandle(IntPtr handle);
	[PreserveSig] int GetService(ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
	[PreserveSig] int IsOffloadCapable(int category, out int offloadCapable);
	[PreserveSig] int SetClientProperties(ref AudioClientProperties properties);
	[PreserveSig] int GetBufferSizeLimits(IntPtr format, int eventDriven, out long minDuration, out long maxDuration);
}

[ComImport, Guid("C8ADBD64-E71E-48A0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IAudioCaptureClient
{
	[PreserveSig] int GetBuffer(out IntPtr data, out uint frames, out uint flags, out ulong pos, out ulong qpc);
	[PreserveSig] int ReleaseBuffer(uint frames);
	[PreserveSig] int GetNextPacketSize(out uint frames);
}

[ComImport, Guid("870AF99C-171D-4F9E-AF0D-E63DF40C2BC9")]
internal class PolicyConfigClient { }

[ComImport, Guid("F8679F50-850A-41CF-9C72-430F290290C8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IPolicyConfig
{
	[PreserveSig] int GetMixFormat([MarshalAs(UnmanagedType.LPWStr)] string id, out IntPtr format);
	[PreserveSig] int GetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id, int def, out IntPtr format);
	[PreserveSig] int ResetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id);
	[PreserveSig] int SetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr endpoint, IntPtr mix);
	[PreserveSig] int GetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string id, int def, IntPtr d1, IntPtr d2);
	[PreserveSig] int SetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr period);
	[PreserveSig] int GetShareMode([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr mode);
	[PreserveSig] int SetShareMode([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr mode);
	[PreserveSig] int GetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string id, int fx, IntPtr key, IntPtr pv);
	[PreserveSig] int SetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string id, int fx, IntPtr key, IntPtr pv);
	[PreserveSig] int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string id, int role);
	[PreserveSig] int SetEndpointVisibility([MarshalAs(UnmanagedType.LPWStr)] string id, int visible);
}

[ComImport, Guid("294935CE-F637-4E7C-A41B-AB255460B862")]
internal class PolicyConfigVistaClient { }

[ComImport, Guid("568B9108-44BF-40B4-9006-86AFE5B5A620"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IPolicyConfigVista
{
	[PreserveSig] int GetMixFormat([MarshalAs(UnmanagedType.LPWStr)] string id, out IntPtr format);
	[PreserveSig] int GetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id, int def, out IntPtr format);
	[PreserveSig] int ResetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id);
	[PreserveSig] int SetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr endpoint, IntPtr mix);
	[PreserveSig] int GetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string id, int def, IntPtr d1, IntPtr d2);
	[PreserveSig] int SetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr period);
	[PreserveSig] int GetShareMode([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr mode);
	[PreserveSig] int SetShareMode([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr mode);
	[PreserveSig] int GetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string id, int fx, IntPtr key, IntPtr pv);
	[PreserveSig] int SetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string id, int fx, IntPtr key, IntPtr pv);
	[PreserveSig] int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string id, int role);
	[PreserveSig] int SetEndpointVisibility([MarshalAs(UnmanagedType.LPWStr)] string id, int visible);
}
