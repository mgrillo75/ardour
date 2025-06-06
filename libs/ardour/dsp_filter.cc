/*
 * Copyright (C) 2016-2017 Paul Davis <paul@linuxaudiosystems.com>
 * Copyright (C) 2016-2018 Robin Gareus <robin@gareus.org>
 * Copyright (C) 2004-2018 Fons Adriaensen <fons@linuxaudio.org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <algorithm>
#include <cmath>
#include <stdlib.h>

#include "ardour/ardour.h"
#include "ardour/buffer.h"
#include "ardour/dB.h"
#include "ardour/dsp_filter.h"
#include "ardour/runtime_functions.h"

#ifdef COMPILER_MSVC
#include <float.h>
#define isfinite_local(val) (bool)_finite ((double)val)
#else
#define isfinite_local std::isfinite
#endif

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

using namespace ARDOUR::DSP;

void
ARDOUR::DSP::memset (float* data, const float val, const uint32_t n_samples)
{
	for (uint32_t i = 0; i < n_samples; ++i) {
		data[i] = val;
	}
}

void
ARDOUR::DSP::mmult (float* data, float* mult, const uint32_t n_samples)
{
	for (uint32_t i = 0; i < n_samples; ++i) {
		data[i] *= mult[i];
	}
}

float
ARDOUR::DSP::log_meter (float power)
{
	// compare to libs/ardour/log_meter.h
	static const float lower_db      = -192.f;
	static const float upper_db      = 0.f;
	static const float non_linearity = 8.0;
	return (power < lower_db ? 0.0 : powf ((power - lower_db) / (upper_db - lower_db), non_linearity));
}

float
ARDOUR::DSP::log_meter_coeff (float coeff)
{
	if (coeff <= 0) {
		return 0;
	}
	return log_meter (fast_coefficient_to_dB (coeff));
}

void
ARDOUR::DSP::peaks (const float* data, float& min, float& max, uint32_t n_samples)
{
	ARDOUR::find_peaks (data, n_samples, &min, &max);
}

void
ARDOUR::DSP::process_map (BufferSet* bufs, const ChanCount& n_out, const ChanMapping& in_map, const ChanMapping& out_map, pframes_t nframes, samplecnt_t offset)
{
	/* PluginInsert already handles most, in particular `no-inplace` buffers in case
	 * or x-over connections, and through connections.
	 *
	 * This just fills output buffers, forwarding inputs as needed:
	 * Input -> plugin-sink == plugin-src -> Output
	 */
	for (DataType::iterator t = DataType::begin (); t != DataType::end (); ++t) {
		for (uint32_t out = 0; out < n_out.get (*t); ++out) {
			bool     valid;
			uint32_t out_idx = out_map.get (*t, out, &valid);
			if (!valid) {
				continue;
			}
			uint32_t in_idx = in_map.get (*t, out, &valid);
			if (!valid) {
				bufs->get_available (*t, out_idx).silence (nframes, offset);
				continue;
			}
			if (in_idx != out_idx) {
				bufs->get_available (*t, out_idx).read_from (bufs->get_available (*t, in_idx), nframes, offset, offset);
			}
		}
	}
}

LowPass::LowPass (double samplerate, float freq)
	: _rate (samplerate)
	, _z (0)
{
	set_cutoff (freq);
}

void
LowPass::set_cutoff (float freq)
{
	_a = 1.f - expf (-2.f * M_PI * freq / _rate);
}

void
LowPass::proc (float* data, const uint32_t n_samples)
{
	// localize variables
	const float a = _a;
	float       z = _z;
	for (uint32_t i = 0; i < n_samples; ++i) {
		data[i] += a * (data[i] - z);
		z = data[i];
	}
	_z = z;
	if (!isfinite_local (_z)) {
		_z = 0;
	} else if (!std::isnormal (_z)) {
		_z = 0;
	}
}

void
LowPass::ctrl (float* data, const float val, const uint32_t n_samples)
{
	// localize variables
	const float a = _a;
	float       z = _z;
	for (uint32_t i = 0; i < n_samples; ++i) {
		data[i] += a * (val - z);
		z = data[i];
	}
	_z = z;
}

/* ****************************************************************************/

Biquad::Biquad (double samplerate)
	: _rate (samplerate)
	, _z1 (0.0)
	, _z2 (0.0)
	, _a1 (0.0)
	, _a2 (0.0)
	, _b0 (1.0)
	, _b1 (0.0)
	, _b2 (0.0)
{
}

Biquad::Biquad (const Biquad& other)
	: _rate (other._rate)
	, _z1 (0.0)
	, _z2 (0.0)
	, _a1 (other._a1)
	, _a2 (other._a2)
	, _b0 (other._b0)
	, _b1 (other._b1)
	, _b2 (other._b2)
{
}

void
Biquad::run (float* data, const uint32_t n_samples)
{
	for (uint32_t i = 0; i < n_samples; ++i) {
		const float xn = data[i];
		const float z  = _b0 * xn + _z1;
		_z1            = _b1 * xn - _a1 * z + _z2;
		_z2            = _b2 * xn - _a2 * z;
		data[i]        = z;
	}

	if (!isfinite_local (_z1)) {
		_z1 = 0;
	} else if (!std::isnormal (_z1)) {
		_z1 = 0;
	}
	if (!isfinite_local (_z2)) {
		_z2 = 0;
	} else if (!std::isnormal (_z2)) {
		_z2 = 0;
	}
}

void
Biquad::configure (double a1, double a2, double b0, double b1, double b2)
{
	_a1 = a1;
	_a2 = a2;
	_b0 = b0;
	_b1 = b1;
	_b2 = b2;
}

void
Biquad::coefficients (double& a1, double& a2, double& b0, double& b1, double& b2) const
{
	a1 = _a1;
	a2 = _a2;
	b0 = _b0;
	b1 = _b1;
	b2 = _b2;
}

void
Biquad::configure (Biquad const& other)
{
	_a1 = other._a1;
	_a2 = other._a2;
	_b0 = other._b0;
	_b1 = other._b1;
	_b2 = other._b2;
}

void
Biquad::set_vicanek_poles (const double W0, const double Q, const double A)
{
	/* https://www.vicanek.de/articles/BiquadFits.pdf */
	const double Q2 = Q * Q;
	const double AA = A * A;
	const double p  = 1. / (4 * AA * Q2);

	_a2 = exp (-.5 * W0 / (A * Q));
	_a1 = p <= 1.
	          ? -2 * _a2 * cos (W0 * sqrt (1 - p))
	          : -2 * _a2 * cosh (W0 * sqrt (p - 1));
	_a2 = _a2 * _a2;
}

void
Biquad::calc_vicanek (const double W0, double& A0, double& A1, double& A2, double& phi0, double& phi1, double& phi2)
{
#define SQR(x) ((x) * (x))
	A0 = SQR (1. + _a1 + _a2);
	A1 = SQR (1. - _a1 + _a2);
	A2 = -4 * _a2;

	phi1 = SQR (sin (.5 * W0));
	phi0 = 1.0 - phi1;
	phi2 = 4 * phi0 * phi1;
#undef SQR
}

void
Biquad::compute (Type type, double freq, double Q, double gain)
{
	if (Q <= .001) {
		Q = 0.001;
	}
	if (freq <= 1.) {
		freq = 1.;
	}
	if (freq >= 0.4998 * _rate) {
		freq = 0.4998 * _rate;
	}

	/* Compute biquad filter settings.
	 * Based on 'Cookbook formulae for audio EQ biquad filter coefficents'
	 * by Robert Bristow-Johnson
	 */
	const double A  = pow (10.0, (gain / 40.0));
	const double W0 = (2.0 * M_PI * freq) / _rate;

	const double sinW0 = sin (W0);
	const double cosW0 = cos (W0);
	const double alpha = sinW0 / (2.0 * Q);
	const double beta  = sqrt (A) / Q;

	double _a0;
	double A0, A1, A2;
	double phi0, phi1, phi2;

	switch (type) {
		case LowPass:
			_b0 = (1.0 - cosW0) / 2.0;
			_b1 =  1.0 - cosW0;
			_b2 = (1.0 - cosW0) / 2.0;
			_a0 =  1.0 + alpha;
			_a1 = -2.0 * cosW0;
			_a2 =  1.0 - alpha;
			break;

		case HighPass:
			_b0 =  (1.0 + cosW0) / 2.0;
			_b1 = -(1.0 + cosW0);
			_b2 =  (1.0 + cosW0) / 2.0;
			_a0 =   1.0 + alpha;
			_a1 =  -2.0 * cosW0;
			_a2 =   1.0 - alpha;
			break;

		case BandPassSkirt: /* Constant skirt gain, peak gain = Q */
			_b0 =  sinW0 / 2.0;
			_b1 =  0.0;
			_b2 = -sinW0 / 2.0;
			_a0 =  1.0 + alpha;
			_a1 = -2.0 * cosW0;
			_a2 =  1.0 - alpha;
			break;

		case BandPass0dB: /* Constant 0 dB peak gain */
			_b0 =  alpha;
			_b1 =  0.0;
			_b2 = -alpha;
			_a0 =  1.0 + alpha;
			_a1 = -2.0 * cosW0;
			_a2 =  1.0 - alpha;
			break;

		case Notch:
			_b0 =  1.0;
			_b1 = -2.0 * cosW0;
			_b2 =  1.0;
			_a0 =  1.0 + alpha;
			_a1 = -2.0 * cosW0;
			_a2 =  1.0 - alpha;
			break;

		case AllPass:
			_b0 =  1.0 - alpha;
			_b1 = -2.0 * cosW0;
			_b2 =  1.0 + alpha;
			_a0 =  1.0 + alpha;
			_a1 = -2.0 * cosW0;
			_a2 =  1.0 - alpha;
			break;

		case Peaking:
			_b0 =  1.0 + (alpha * A);
			_b1 = -2.0 * cosW0;
			_b2 =  1.0 - (alpha * A);
			_a0 =  1.0 + (alpha / A);
			_a1 = -2.0 * cosW0;
			_a2 =  1.0 - (alpha / A);
			break;

		case LowShelf:
			_b0 =         A * ((A + 1) - ((A - 1) * cosW0) + (beta * sinW0));
			_b1 = (2.0 * A) * ((A - 1) - ((A + 1) * cosW0));
			_b2 =         A * ((A + 1) - ((A - 1) * cosW0) - (beta * sinW0));
			_a0 =              (A + 1) + ((A - 1) * cosW0) + (beta * sinW0);
			_a1 =      -2.0 * ((A - 1) + ((A + 1) * cosW0));
			_a2 =              (A + 1) + ((A - 1) * cosW0) - (beta * sinW0);
			break;

		case HighShelf:
			_b0 =          A * ((A + 1) + ((A - 1) * cosW0) + (beta * sinW0));
			_b1 = -(2.0 * A) * ((A - 1) + ((A + 1) * cosW0));
			_b2 =          A * ((A + 1) + ((A - 1) * cosW0) - (beta * sinW0));
			_a0 =               (A + 1) - ((A - 1) * cosW0) + (beta * sinW0);
			_a1 =        2.0 * ((A - 1) - ((A + 1) * cosW0));
			_a2 =               (A + 1) - ((A - 1) * cosW0) - (beta * sinW0);
			break;

		case MatchedHighPass:
			_a0 = 1.0;
			set_vicanek_poles (W0, Q);
			calc_vicanek (W0, A0, A1, A2, phi0, phi1, phi2);

			_b0 = sqrt (A0 * phi0 + A1 * phi1 + A2 * phi2) / (4 * phi1) * Q;
			_b1 = -2 * _b0;
			_b2 = _b0;
			break;

		case MatchedLowPass:
			_a0 = 1.0;
			set_vicanek_poles (W0, Q);
			calc_vicanek (W0, A0, A1, A2, phi0, phi1, phi2);
			{
				const double B0_2 = 1 + _a1 + _a2; // = sqrt (B0)
				const double B1   = ((A0 * phi0 + A1 * phi1 + A2 * phi2) * Q * Q - A0 * phi0) / phi1;

				_b0 = .5 * (B0_2 + sqrt (B1));
				_b1 = B0_2 - _b0;
				_b2 = 0;
			}
			break;

		case MatchedBandPass0dB: /* Constant 0 dB peak gain */
			_a0 = 1.0;
			set_vicanek_poles (W0, Q);
			{
				float fq  = 2 * freq / _rate;
				float fq2 = fq * fq;

				_b1 = -.5 * (1 - _a1 + _a2) * fq / Q / sqrt ((1 - fq2) * (1 - fq2) + fq2 / (Q * Q));
				_b0 = .5 * ((1 + _a1 + _a2) / (W0 * Q) - _b1);
				_b2 = -_b0 - _b1;
			}
			break;

		case MatchedPeaking:
			_a0 = 1.0;
			set_vicanek_poles (W0, Q, A);
			calc_vicanek (W0, A0, A1, A2, phi0, phi1, phi2);
			{
				const double AA   = A * A;
				const double AAAA = AA * AA;

				const double R1 = (phi0 * A0 + phi1 * A1 + phi2 * A2) * AAAA;
				const double R2 = (A1 - A0 + 4 * (phi0 - phi1) * A2) * AAAA;

				const double B0 = A0;
				const double B2 = (R1 - phi1 * R2 - B0) / (4 * phi1 * phi1);
				const double B1 = R2 + B0 + 4 * (phi1 - phi0) * B2;

				const double B0_2 = 1 + _a1 + _a2; // = sqrt (B0)

				_b1 = .5 * (B0_2 - sqrt (B1));

				const double w = B0_2 - _b1;

				_b0 = .5 * (w + sqrt (w * w + B2));
				_b2 = -B2 / (4 * _b0);
			}
			break;

		default:
			abort (); /*NOTREACHED*/
			break;
	}

	_b0 /= _a0;
	_b1 /= _a0;
	_b2 /= _a0;
	_a1 /= _a0;
	_a2 /= _a0;
}

float
Biquad::dB_at_freq (float freq) const
{
	const double W0 = (2.0 * M_PI * freq) / _rate;
	const float  c1 = cosf (W0);
	const float  s1 = sinf (W0);

	const float A = _b0 + _b2;
	const float B = _b0 - _b2;
	const float C = 1.0 + _a2;
	const float D = 1.0 - _a2;

	const float a = A * c1 + _b1;
	const float b = B * s1;
	const float c = C * c1 + _a1;
	const float d = D * s1;

#define SQUARE(x) ((x) * (x))
	float rv = 20.f * log10f (sqrtf ((SQUARE (a) + SQUARE (b)) * (SQUARE (c) + SQUARE (d))) / (SQUARE (c) + SQUARE (d)));
	if (!isfinite_local (rv)) {
		rv = 0;
	}
	return std::min (120.f, std::max (-120.f, rv));
}

/* ****************************************************************************/

FFTSpectrum::FFTSpectrum (uint32_t window_size, double rate)
	: hann_window (0)
{
	init (window_size, rate);
}

FFTSpectrum::~FFTSpectrum ()
{
	{
		Glib::Threads::Mutex::Lock lk (ARDOUR::fft_planner_lock);
		fftwf_destroy_plan (_fftplan);
	}
	fftwf_free (_fft_data_in);
	fftwf_free (_fft_data_out);
	free (_fft_power);
	free (hann_window);
}

void
FFTSpectrum::init (uint32_t window_size, double rate)
{
	assert (window_size > 0);
	Glib::Threads::Mutex::Lock lk (ARDOUR::fft_planner_lock);

	_fft_window_size  = window_size;
	_fft_data_size    = window_size / 2;
	_fft_freq_per_bin = rate / _fft_data_size / 2.f;

	_fft_data_in  = (float*)fftwf_malloc (sizeof (float) * _fft_window_size);
	_fft_data_out = (float*)fftwf_malloc (sizeof (float) * _fft_window_size);
	_fft_power    = (float*)malloc (sizeof (float) * _fft_data_size);

	reset ();

	_fftplan = fftwf_plan_r2r_1d (_fft_window_size, _fft_data_in, _fft_data_out, FFTW_R2HC, FFTW_MEASURE);

	hann_window = (float*)malloc (sizeof (float) * window_size);
	double sum  = 0.0;

	for (uint32_t i = 0; i < window_size; ++i) {
		hann_window[i] = 0.5f - (0.5f * (float)cos (2.0f * M_PI * (float)i / (float)(window_size)));
		sum += hann_window[i];
	}
	const double isum = 2.0 / sum;
	for (uint32_t i = 0; i < window_size; ++i) {
		hann_window[i] *= isum;
	}
}

void
FFTSpectrum::reset ()
{
	for (uint32_t i = 0; i < _fft_data_size; ++i) {
		_fft_power[i] = 0;
	}
	for (uint32_t i = 0; i < _fft_window_size; ++i) {
		_fft_data_out[i] = 0;
	}
}

void
FFTSpectrum::set_data_hann (float const* const data, uint32_t n_samples, uint32_t offset)
{
	assert (n_samples + offset <= _fft_window_size);
	for (uint32_t i = 0; i < n_samples; ++i) {
		_fft_data_in[i + offset] = data[i] * hann_window[i + offset];
	}
}

void
FFTSpectrum::execute ()
{
	fftwf_execute (_fftplan);

	_fft_power[0] = _fft_data_out[0] * _fft_data_out[0];

#define FRe (_fft_data_out[i])
#define FIm (_fft_data_out[_fft_window_size - i])
	for (uint32_t i = 1; i < _fft_data_size - 1; ++i) {
		_fft_power[i] = (FRe * FRe) + (FIm * FIm);
		//_fft_phase[i] = atan2f (FIm, FRe);
	}
#undef FRe
#undef FIm
}

float
FFTSpectrum::power_at_bin (const uint32_t b, const float gain, bool pink) const
{
	assert (b < _fft_data_size);
	const float a = _fft_power[b] * gain * (pink ? b : 1.f);
	return a > 1e-12 ? 10.0 * fast_log10 (a) : -INFINITY;
}

/* ****************************************************************************/

PerceptualAnalyzer::Trace::Trace (int size)
	: _valid (false)
{
	_data = new float [size];
}

PerceptualAnalyzer::Trace::~Trace ()
{
	delete[] _data;
}

PerceptualAnalyzer::PerceptualAnalyzer (double sample_rate, int ipsize)
	: _ipsize (ipsize)
	, _icount (0)
	, _fftplan (0)
	, _fsamp (sample_rate)
	, _wfact (0.9f)
	, _speed (1.0f)
{
	_ipdata = new float [ipsize];
	_warped = (float *) fftwf_malloc ((_fftlen + 1) * sizeof (float));
	_trdata = (fftwf_complex *) fftwf_malloc ((_fftlen / 2 + 9) * sizeof (fftwf_complex));
	_power = new Trace (_fftlen + 1);
	_peakp = new Trace (_fftlen + 1);

	init ();
}

PerceptualAnalyzer::~PerceptualAnalyzer ()
{
	if (_fftplan) {
		Glib::Threads::Mutex::Lock lk (ARDOUR::fft_planner_lock);
		fftwf_destroy_plan (_fftplan);
	}
	delete _power;
	delete _peakp;
	fftwf_free (_trdata);
	fftwf_free (_warped);
	delete[] _ipdata;
}

void
PerceptualAnalyzer::init ()
{
	Glib::Threads::Mutex::Lock lk (ARDOUR::fft_planner_lock);
	if (_fftplan) {
		fftwf_destroy_plan (_fftplan);
	}
	_fftplan = fftwf_plan_dft_r2c_1d (_fftlen, _warped, _trdata + 4, FFTW_ESTIMATE);
	set_wfact (_wfact);
	set_speed (_speed);
}

void
PerceptualAnalyzer::set_wfact (Warp warp)
{
	float wfact;
	switch (warp) {
		case Bark:
			wfact = 0.8517f * sqrtf (atanf (65.83e-6f * _fsamp)) - 0.1916f;
			break;
		case Medium:
			wfact = 0.90;
			break;
		case High:
			wfact = 0.95;
			break;
	}
	set_wfact (wfact);
}

void
PerceptualAnalyzer::set_wfact (float wfact)
{
	_wfact = wfact;

	reset ();

	for (int i = 0; i <= _fftlen; ++i) {
		const double f = 0.5 * i / _fftlen;
		_fscale [i] = warp_freq (-wfact, f);
	}
	for (int i = 1; i < _fftlen; ++i) {
		_bwcorr [i] = 30.0f * (_fscale [i + 1] - _fscale [i - 1]) / _fscale [i];
	}

	_bwcorr [0]       = _bwcorr [1];
	_bwcorr [_fftlen] = _bwcorr [_fftlen - 1];
}

void
PerceptualAnalyzer::set_speed (Speed speed)
{
	switch (speed) {
		case Noise:
			_speed = 20.0;
			break;
		case Slow:
			_speed = 2.0;
			break;
		case Moderate:
			_speed = 0.2;
			break;
		case Fast:
			_speed = 0.08;
			break;
		case Rapid:
			_speed = 0.03;
			break;
	}
}

void
PerceptualAnalyzer::set_speed (float speed)
{
	_speed = speed;
}

void
PerceptualAnalyzer::reset ()
{
	_power->_valid = false;
	_peakp->_valid = false;
	_peakp->_count = 0;
	::memset (_warped, 0, (_fftlen + 1) * sizeof (float));
	::memset (_power->_data,  0, (_fftlen + 1) * sizeof (float));
	::memset (_peakp->_data,  0, (_fftlen + 1) * sizeof (float));
}

float
PerceptualAnalyzer::conv0 (fftwf_complex *v)
{
	float x, y;
	x =  v [0][0]
	    - 0.677014f * (v [-1][0] + v [1][0])
	    + 0.195602f * (v [-2][0] + v [2][0])
	    - 0.019420f * (v [-3][0] + v [3][0])
	    + 0.000741f * (v [-4][0] + v [4][0]);
	y =  v [0][1]
	    - 0.677014f * (v [-1][1] + v [1][1])
	    + 0.195602f * (v [-2][1] + v [2][1])
	    - 0.019420f * (v [-3][1] + v [3][1])
	    + 0.000741f * (v [-4][1] + v [4][1]);
	return x * x + y * y;
}

float PerceptualAnalyzer::conv1 (fftwf_complex *v)
{
	float x, y;
	x =   0.908040f * (v [ 0][0] - v [1][0])
	    - 0.409037f * (v [-1][0] - v [2][0])
	    + 0.071556f * (v [-2][0] - v [3][0])
	    - 0.004085f * (v [-3][0] - v [4][0]);
	y =   0.908040f * (v [ 0][1] - v [1][1])
	    - 0.409037f * (v [-1][1] - v [2][1])
	    + 0.071556f * (v [-2][1] - v [3][1])
	    - 0.004085f * (v [-3][1] - v [4][1]);
	return x * x + y * y;
}

void
PerceptualAnalyzer::process (int iplen, ProcessMode mode)
{
	int    i, j, k, l, n;
	float  a, b, c, d, m, p, s, w, z;
	float  *p1, *p2;

	w = -_wfact;
	l = _fftlen / 2;

	for (k = 0; k < iplen; k += l) {
		p1 = _ipdata + _icount;
		_icount += l;
		if (_icount == _ipsize) {
			_icount = 0;
		}

		for (j = 0; j < l; j += 4) {
			a = _warped [0];
			b = *p1++ + 1e-20f;
			c = *p1++ - 1e-20f;
			d = *p1++ + 1e-20f;
			_warped [0] = z = *p1++ - 1e-20f;

			for (i = 0; i < _fftlen; i += 4) {
				s = _warped [i + 1];
				a += w * (b - s);
				b += w * (c - a);
				c += w * (d - b);
				_warped [i + 1] = z = d + w * (z - c);
				d = s;
				s = _warped [i + 2];
				d += w * (a - s);
				a += w * (b - d);
				b += w * (c - a);
				_warped [i + 2] = z = c + w * (z - b);
				c = s;
				s = _warped [i + 3];
				c += w * (d - s);
				d += w * (a - c);
				a += w * (b - d);
				_warped [i + 3] = z = b + w * (z - a);
				b = s;
				s = _warped [i + 4];
				b += w * (c - s);
				c += w * (d - b);
				d += w * (a - c);
				_warped [i + 4] = z = a + w * (z - d);
				a = s;
			}
		}

		fftwf_execute (_fftplan);

		for (i = 1; i <= 4; i++) {
			_trdata [4 - i][0]     =  _trdata [4 + i][0];
			_trdata [4 - i][1]     = -_trdata [4 + i][1];
			_trdata [4 + l + i][0] =  _trdata [4 + l - i][0];
			_trdata [4 + l + i][1] = -_trdata [4 + l - i][1];
		}

		a = 1.0f - powf (0.1f, l / (_fsamp * _speed));
		b = 4.0f / ((float)_fftlen * (float)_fftlen);
		s = 0;
		m = 0;
		p1 = _power->_data;

		for (i = 0; i < l; i++) {
			p = b * conv0 (_trdata + 4 + i) + 1e-20f;
			if (m < p) {
				m = p;
			}
			s += p;
			*p1 += a * (p - *p1);
			p1++;
			p = b * conv1 (_trdata + 4 + i) + 1e-20f;
			if (m < p) {
				m = p;
			}
			s += p;
			*p1 += a * (p - *p1);
			p1++;
		}

		p = b * conv0 (_trdata + 4 + i) + 1e-20f;
		s += p;
		*p1 += a * (p - *p1);
		_power->_valid = true;

		if (_pmax < m) {
			_pmax = m;
		} else {
			_pmax *= 0.95f;
		}

		if (mode == MM_PEAK) {
			p1 = _power->_data;
			p2 = _peakp->_data;
			for (i = 0; i <= 2 * l; i++) {
				if (p2 [i] < p1 [i]) p2 [i] = p1 [i];
			}
			_peakp->_valid = true;
		} else if (mode == MM_AVER) {
			p1 = _power->_data;
			p2 = _peakp->_data;
			n = _peakp->_count;
			a = n;
			b = a + 1;
			for (i = 0; i <= 2 * l; i++) {
				p2 [i] = (a * p2 [i] + p1 [i]) / b;
			}
			if (n < 1000000) _peakp->_count = n + 1;
			_peakp->_valid = true;
		}
	}
}

double
PerceptualAnalyzer::warp_freq (double w, double f)
{
	f *= 2 * M_PI;
	return fabs (atan2 ((1 - w * w) * sin (f), (1 + w * w) * cos (f) - 2 * w) / (2 * M_PI));
}

float
PerceptualAnalyzer::freq_at_bin (const uint32_t bin) const
{
	assert (bin <= _fftlen);
	return _fscale [bin] * _fsamp;
}

float
PerceptualAnalyzer::power_at_bin (const uint32_t b, float gain, bool pink) const
{
	assert (b <= _fftlen);
	if (!pink) {
		return 10.f * log10f (_power->_data[b] + 1e-30);
	} else {
		/* proportional */
		return 10.f * log10f ((_power->_data[b] + 1e-30) / _bwcorr[b]);
	}
}

/* ****************************************************************************/
StereoCorrelation::StereoCorrelation (float samplerate, float lp_freq, float tc_corr)
{
	_w1 = 6.28f * lp_freq / samplerate;
	_w2 = 1.f / (tc_corr * samplerate);
	reset ();
}

void
StereoCorrelation::reset ()
{
	_zl  = 0;
	_zr  = 0;
	_zlr = 0;
	_zll = 0;
	_zrr = 0;
}

float
StereoCorrelation::read () const
{
	return _zlr / sqrtf (_zll * _zrr + 1e-10f);
}

void
StereoCorrelation::process (float const* pl, float const* pr, uint32_t n)
{
	float zl, zr, zlr, zll, zrr;

	zl  = _zl;
	zr  = _zr;
	zlr = _zlr;
	zll = _zll;
	zrr = _zrr;
	while (n--) {
		zl += _w1 * (*pl++ - zl) + 1e-20f;
		zr += _w1 * (*pr++ - zr) + 1e-20f;
		zlr += _w2 * (zl * zr - zlr);
		zll += _w2 * (zl * zl - zll);
		zrr += _w2 * (zr * zr - zrr);
	}

	if (!isfinite (zl)) {
		zl = 0;
	}
	if (!isfinite (zr)) {
		zr = 0;
	}
	if (!isfinite (zlr)) {
		zlr = 0;
	}
	if (!isfinite (zll)) {
		zll = 0;
	}
	if (!isfinite (zrr)) {
		zrr = 0;
	}

	_zl  = zl;
	_zr  = zr;
	_zlr = zlr + 1e-10f;
	_zll = zll + 1e-10f;
	_zrr = zrr + 1e-10f;
}

/* ****************************************************************************/

Generator::Generator ()
	: _type (UniformWhiteNoise)
	, _rseed (1)
{
	set_type (UniformWhiteNoise);
}

void
Generator::set_type (Generator::Type t)
{
	_type = t;
	_b0 = _b1 = _b2 = _b3 = _b4 = _b5 = _b6 = 0;
	_pass = false;
	_rn = 0;
}

void
Generator::run (float* data, const uint32_t n_samples)
{
	switch (_type) {
		default:
		case UniformWhiteNoise:
			for (uint32_t i = 0; i < n_samples; ++i) {
				data[i] = randf ();
			}
			break;
		case GaussianWhiteNoise:
			for (uint32_t i = 0; i < n_samples; ++i) {
				data[i] = 0.7079f * grandf ();
			}
			break;
		case PinkNoise:
			for (uint32_t i = 0; i < n_samples; ++i) {
				const float white = .39572f * randf ();
				_b0 = .99886f * _b0 + white * .0555179f;
				_b1 = .99332f * _b1 + white * .0750759f;
				_b2 = .96900f * _b2 + white * .1538520f;
				_b3 = .86650f * _b3 + white * .3104856f;
				_b4 = .55000f * _b4 + white * .5329522f;
				_b5 = -.7616f * _b5 - white * .0168980f;
				data[i] = _b0 + _b1 + _b2 + _b3 + _b4 + _b5 + _b6 + white * 0.5362f;
				_b6 = white * 0.115926f;
			}
			break;
	}
}

inline uint32_t
Generator::randi ()
{
	// 31bit Park-Miller-Carta Pseudo-Random Number Generator
	uint32_t hi, lo;
	lo = 16807 * (_rseed & 0xffff);
	hi = 16807 * (_rseed >> 16);
	lo += (hi & 0x7fff) << 16;
	lo += hi >> 15;
	lo = (lo & 0x7fffffff) + (lo >> 31);
	return (_rseed = lo);
}

inline float
Generator::grandf ()
{
	float x1, x2, r;

	if (_pass) {
		_pass = false;
		return _rn;
	}

	do {
		x1 = randf ();
		x2 = randf ();
		r  = x1 * x1 + x2 * x2;
	} while ((r >= 1.0f) || (r < 1e-22f));

	r = sqrtf (-2.f * logf (r) / r);

	_pass = true;
	_rn   = r * x2;
	return r * x1;
}
