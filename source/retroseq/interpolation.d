///
module retroseq.interpolation;

///
enum InterpolationMethod {
	none, ///
	linear, ///
	cubic, ///
	sinc, ///
	gaussianSNES, ///
}

///
byte interpolate(InterpolationMethod method, scope const byte[] samples, int position) @safe pure nothrow @nogc {
	double[8] floatSamples = [samples[0] / cast(double)byte.max, samples[1] / cast(double)byte.max, samples[2] / cast(double)byte.max, samples[3] / cast(double)byte.max, samples[4] / cast(double)byte.max, samples[5] / cast(double)byte.max, samples[6] / cast(double)byte.max, samples[7] / cast(double)byte.max];
	final switch(method) {
		case InterpolationMethod.none:
			return samples[0];
		case InterpolationMethod.linear:
			return linearInterpolation(samples[0 .. 2], position >> 8);
		case InterpolationMethod.sinc:
			return sincInterpolation(samples[0 .. 8], cast(ushort)(position >> 5));
		case InterpolationMethod.cubic:
			return cubicInterpolation(samples[0 .. 4], cast(ubyte)(position >> 8));
		case InterpolationMethod.gaussianSNES:
			return cast(byte)(gaussianSNESInterpolation(floatSamples[0 .. 4], cast(ubyte)(position >> 8)) * byte.max);
	}
}

///
byte linearInterpolation(byte[2] samples, int position) @safe pure nothrow @nogc {
	return cast(byte)((samples[0]* (0x100 - position) + samples[1] * position) >> 8);
}

///
byte cubicInterpolation(byte[4] latest, ubyte index) nothrow @safe pure @nogc {
	const(short)[] fwd = cubicTable[index .. index + 258];
	const(short)[] rev = cubicTable[256 - index  .. 514 - index]; // mirror left half

	int result;
	result = (fwd[0] * latest[0]);
	result += (fwd[257] * latest[1]);
	result += (rev[257] * latest[2]);
	result += (rev[0] * latest[3]);
	result >>= 11;

	if (cast(byte)result != result) {
		result = (result >> 31) ^ 0x7F;
	}
	return cast(byte)result;
}

///
double gaussianSNESInterpolation(double[4] samples, ubyte index) nothrow @safe pure @nogc {
	const double[4] gauss = [gaussTableSNES[256 - index], gaussTableSNES[511 - index], gaussTableSNES[index + 256], gaussTableSNES[index]];
	return vectorMultiplySum(gauss,  samples);
}

///
T vectorMultiplySum(T, size_t n)(const T[n] a, const T[n] b) {
    import std.algorithm.comparison : clamp;
    T[n] c = a;
	c[] *= b[];
    T result = 0.0;
    foreach (val; c) {
        result += val;
    }
	return clamp(result, -1, 1);
}
///
byte sincInterpolation(byte[8] latest, ushort index) nothrow @safe pure @nogc {
	const(short)[] selection = sincTable[index .. index + 8];

	int result;
	result = (selection[0] >> 3) * latest[0];
	result += (selection[1] >> 3) * latest[1];
	result += (selection[2] >> 3) * latest[2];
	result += (selection[3] >> 3) * latest[3];
	result += (selection[4] >> 3) * latest[4];
	result += (selection[5] >> 3) * latest[5];
	result += (selection[6] >> 3) * latest[6];
	result += (selection[7] >> 3) * latest[7];
	result >>= 14;

	if (cast(byte)result != result) {
		result = (result >> 31) ^ 0x7FFF;
	}
	return cast(byte)result;
}

immutable gaussTableSNES = generateGaussianTableSNES!512(); ///

/// Generate gaussian table for SNES - Based on original code by Ryphecha and Near
double[length] generateGaussianTableSNES(size_t length)() @safe {
   import std.math : cos, PI, round, sin;
   double[length] result;
   double[length] table;
   foreach (index, _; table) {
      double k = 0.5 + index;
      double s = (sin(PI * k * 1.280 / 1024));
      double t = (cos(PI * k * 2.000 / 1023) - 1) * 0.50;
      double u = (cos(PI * k * 4.000 / 1023) - 1) * 0.08;
      double r = s * (t + u + 1.0) / k;
      table[$ - 1 - index] = r;
   }
   foreach (uint phase; 0 .. length / 4) {
      const scale = 1.0 / (table[phase]
            + table[phase + $ / 2]
            + table[$ - 1 - phase]
            + table[$ / 2 - 1 - phase]);
      result[phase] = table[phase] * scale;
      result[phase + $ / 2] = table[phase + $ / 2] * scale;
      result[$ - 1 - phase] = table[$ - 1 - phase] * scale;
      result[$ / 2 - 1 - phase] = table[$ / 2 - 1 - phase] * scale;
   }
   return result;
}

/// The following tables belong to the public domain, and have been used by many emulators.
/// The means to generate them has been lost, however.
immutable short[514] cubicTable =
[
   0,  -4,  -8, -12, -16, -20, -23, -27, -30, -34, -37, -41, -44, -47, -50, -53,
 -56, -59, -62, -65, -68, -71, -73, -76, -78, -81, -84, -87, -89, -91, -93, -95,
 -98,-100,-102,-104,-106,-109,-110,-112,-113,-116,-117,-119,-121,-122,-123,-125,
-126,-128,-129,-131,-132,-134,-134,-136,-136,-138,-138,-140,-141,-141,-142,-143,
-144,-144,-145,-146,-147,-148,-147,-148,-148,-149,-149,-150,-150,-150,-150,-151,
-151,-151,-151,-151,-152,-152,-151,-152,-151,-152,-151,-151,-151,-151,-150,-150,
-150,-149,-149,-149,-149,-148,-147,-147,-146,-146,-145,-145,-144,-144,-143,-142,
-141,-141,-140,-139,-139,-138,-137,-136,-135,-135,-133,-133,-132,-131,-130,-129,
-128,-127,-126,-125,-124,-123,-121,-121,-119,-118,-117,-116,-115,-114,-112,-111,
-110,-109,-107,-106,-105,-104,-102,-102,-100, -99, -97, -97, -95, -94, -92, -91,
 -90, -88, -87, -86, -85, -84, -82, -81, -79, -78, -76, -76, -74, -73, -71, -70,
 -68, -67, -66, -65, -63, -62, -60, -60, -58, -57, -55, -55, -53, -52, -50, -49,
 -48, -46, -45, -44, -43, -42, -40, -39, -38, -37, -36, -35, -34, -32, -31, -30,
 -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -19, -17, -16, -15, -14,
 -14, -13, -12, -11, -11, -10,  -9,  -9,  -8,  -8,  -7,  -7,  -6,  -5,  -4,  -4,
  -3,  -3,  -3,  -2,  -2,  -2,  -1,  -1,   0,  -1,   0,  -1,   0,   0,   0,   0,
   0,
2048,2048,2048,2048,2047,2047,2046,2045,2043,2042,2041,2039,2037,2035,2033,2031,
2028,2026,2024,2021,2018,2015,2012,2009,2005,2002,1999,1995,1991,1987,1982,1978,
1974,1969,1965,1960,1955,1951,1946,1940,1934,1929,1924,1918,1912,1906,1900,1895,
1888,1882,1875,1869,1862,1856,1849,1842,1835,1828,1821,1814,1806,1799,1791,1783,
1776,1768,1760,1753,1744,1737,1728,1720,1711,1703,1695,1686,1677,1668,1659,1651,
1641,1633,1623,1614,1605,1596,1587,1577,1567,1559,1549,1539,1529,1520,1510,1499,
1490,1480,1470,1460,1450,1440,1430,1420,1408,1398,1389,1378,1367,1357,1346,1336,
1325,1315,1304,1293,1282,1272,1261,1250,1239,1229,1218,1207,1196,1185,1174,1163,
1152,1141,1130,1119,1108,1097,1086,1075,1063,1052,1042,1030,1019,1008, 997, 986,
 974, 964, 952, 941, 930, 919, 908, 897, 886, 875, 864, 853, 842, 831, 820, 809,
 798, 787, 776, 765, 754, 744, 733, 722, 711, 700, 690, 679, 668, 658, 647, 637,
 626, 616, 605, 595, 584, 574, 564, 554, 543, 534, 524, 514, 503, 494, 483, 473,
 464, 454, 444, 435, 425, 416, 407, 397, 387, 378, 370, 360, 351, 342, 333, 325,
 315, 307, 298, 290, 281, 273, 265, 256, 248, 241, 233, 225, 216, 209, 201, 193,
 186, 178, 171, 164, 157, 150, 143, 137, 129, 123, 117, 110, 103,  97,  91,  85,
  79,  74,  68,  62,  56,  51,  46,  41,  35,  31,  27,  22,  17,  13,   8,   4,
   0
];

///
immutable short[2048] sincTable = [
    39,  -315,   666, 15642,   666,  -315,    39,   -38,
    38,  -302,   613, 15642,   718,  -328,    41,   -38,
    36,  -288,   561, 15641,   772,  -342,    42,   -38,
    35,  -275,   510, 15639,   826,  -355,    44,   -38,
    33,  -263,   459, 15636,   880,  -369,    46,   -38,
    32,  -250,   408, 15632,   935,  -383,    47,   -38,
    31,  -237,   358, 15628,   990,  -396,    49,   -38,
    29,  -224,   309, 15622,  1046,  -410,    51,   -38,
    28,  -212,   259, 15616,  1103,  -425,    53,   -38,
    27,  -200,   211, 15609,  1159,  -439,    54,   -38,
    25,  -188,   163, 15601,  1216,  -453,    56,   -38,
    24,  -175,   115, 15593,  1274,  -467,    58,   -38,
    23,  -164,    68, 15583,  1332,  -482,    60,   -38,
    22,  -152,    22, 15573,  1391,  -496,    62,   -37,
    21,  -140,   -24, 15562,  1450,  -511,    64,   -37,
    19,  -128,   -70, 15550,  1509,  -526,    66,   -37,
    18,  -117,  -115, 15538,  1569,  -540,    68,   -37,
    17,  -106,  -159, 15524,  1629,  -555,    70,   -37,
    16,   -94,  -203, 15510,  1690,  -570,    72,   -36,
    15,   -83,  -247, 15495,  1751,  -585,    74,   -36,
    14,   -72,  -289, 15479,  1813,  -600,    76,   -36,
    13,   -62,  -332, 15462,  1875,  -616,    79,   -36,
    12,   -51,  -374, 15445,  1937,  -631,    81,   -35,
    11,   -40,  -415, 15426,  2000,  -646,    83,   -35,
    11,   -30,  -456, 15407,  2063,  -662,    85,   -35,
    10,   -20,  -496, 15387,  2127,  -677,    88,   -34,
     9,    -9,  -536, 15366,  2191,  -693,    90,   -34,
     8,     1,  -576, 15345,  2256,  -708,    92,   -34,
     7,    10,  -614, 15323,  2321,  -724,    95,   -33,
     7,    20,  -653, 15300,  2386,  -740,    97,   -33,
     6,    30,  -690, 15276,  2451,  -755,    99,   -33,
     5,    39,  -728, 15251,  2517,  -771,   102,   -32,
     5,    49,  -764, 15226,  2584,  -787,   104,   -32,
     4,    58,  -801, 15200,  2651,  -803,   107,   -32,
     3,    67,  -836, 15173,  2718,  -819,   109,   -31,
     3,    76,  -871, 15145,  2785,  -835,   112,   -31,
     2,    85,  -906, 15117,  2853,  -851,   115,   -30,
     2,    93,  -940, 15087,  2921,  -867,   117,   -30,
     1,   102,  -974, 15057,  2990,  -883,   120,   -29,
     1,   110, -1007, 15027,  3059,  -899,   122,   -29,
     0,   118, -1039, 14995,  3128,  -915,   125,   -29,
     0,   127, -1071, 14963,  3198,  -931,   128,   -28,
    -1,   135, -1103, 14930,  3268,  -948,   131,   -28,
    -1,   142, -1134, 14896,  3338,  -964,   133,   -27,
    -1,   150, -1164, 14862,  3409,  -980,   136,   -27,
    -2,   158, -1194, 14827,  3480,  -996,   139,   -26,
    -2,   165, -1224, 14791,  3551, -1013,   142,   -26,
    -3,   172, -1253, 14754,  3622, -1029,   144,   -25,
    -3,   179, -1281, 14717,  3694, -1045,   147,   -25,
    -3,   187, -1309, 14679,  3766, -1062,   150,   -24,
    -3,   193, -1337, 14640,  3839, -1078,   153,   -24,
    -4,   200, -1363, 14601,  3912, -1094,   156,   -23,
    -4,   207, -1390, 14561,  3985, -1110,   159,   -23,
    -4,   213, -1416, 14520,  4058, -1127,   162,   -22,
    -4,   220, -1441, 14479,  4131, -1143,   165,   -22,
    -4,   226, -1466, 14437,  4205, -1159,   168,   -22,
    -5,   232, -1490, 14394,  4279, -1175,   171,   -21,
    -5,   238, -1514, 14350,  4354, -1192,   174,   -21,
    -5,   244, -1537, 14306,  4428, -1208,   177,   -20,
    -5,   249, -1560, 14261,  4503, -1224,   180,   -20,
    -5,   255, -1583, 14216,  4578, -1240,   183,   -19,
    -5,   260, -1604, 14169,  4653, -1256,   186,   -19,
    -5,   265, -1626, 14123,  4729, -1272,   189,   -18,
    -5,   271, -1647, 14075,  4805, -1288,   192,   -18,
    -5,   276, -1667, 14027,  4881, -1304,   195,   -17,
    -6,   280, -1687, 13978,  4957, -1320,   198,   -17,
    -6,   285, -1706, 13929,  5033, -1336,   201,   -16,
    -6,   290, -1725, 13879,  5110, -1352,   204,   -16,
    -6,   294, -1744, 13829,  5186, -1368,   207,   -15,
    -6,   299, -1762, 13777,  5263, -1383,   210,   -15,
    -6,   303, -1779, 13726,  5340, -1399,   213,   -14,
    -6,   307, -1796, 13673,  5418, -1414,   216,   -14,
    -6,   311, -1813, 13620,  5495, -1430,   219,   -13,
    -5,   315, -1829, 13567,  5573, -1445,   222,   -13,
    -5,   319, -1844, 13512,  5651, -1461,   225,   -13,
    -5,   322, -1859, 13458,  5728, -1476,   229,   -12,
    -5,   326, -1874, 13402,  5806, -1491,   232,   -12,
    -5,   329, -1888, 13347,  5885, -1506,   235,   -11,
    -5,   332, -1902, 13290,  5963, -1521,   238,   -11,
    -5,   335, -1915, 13233,  6041, -1536,   241,   -10,
    -5,   338, -1928, 13176,  6120, -1551,   244,   -10,
    -5,   341, -1940, 13118,  6199, -1566,   247,   -10,
    -5,   344, -1952, 13059,  6277, -1580,   250,    -9,
    -5,   347, -1964, 13000,  6356, -1595,   253,    -9,
    -5,   349, -1975, 12940,  6435, -1609,   256,    -8,
    -4,   352, -1986, 12880,  6514, -1623,   259,    -8,
    -4,   354, -1996, 12819,  6594, -1637,   262,    -8,
    -4,   356, -2005, 12758,  6673, -1651,   265,    -7,
    -4,   358, -2015, 12696,  6752, -1665,   268,    -7,
    -4,   360, -2024, 12634,  6831, -1679,   271,    -7,
    -4,   362, -2032, 12572,  6911, -1693,   274,    -6,
    -4,   364, -2040, 12509,  6990, -1706,   277,    -6,
    -4,   366, -2048, 12445,  7070, -1719,   280,    -6,
    -3,   367, -2055, 12381,  7149, -1732,   283,    -5,
    -3,   369, -2062, 12316,  7229, -1745,   286,    -5,
    -3,   370, -2068, 12251,  7308, -1758,   289,    -5,
    -3,   371, -2074, 12186,  7388, -1771,   291,    -4,
    -3,   372, -2079, 12120,  7467, -1784,   294,    -4,
    -3,   373, -2084, 12054,  7547, -1796,   297,    -4,
    -3,   374, -2089, 11987,  7626, -1808,   300,    -4,
    -2,   375, -2094, 11920,  7706, -1820,   303,    -3,
    -2,   376, -2098, 11852,  7785, -1832,   305,    -3,
    -2,   376, -2101, 11785,  7865, -1844,   308,    -3,
    -2,   377, -2104, 11716,  7944, -1855,   311,    -3,
    -2,   377, -2107, 11647,  8024, -1866,   313,    -2,
    -2,   378, -2110, 11578,  8103, -1877,   316,    -2,
    -2,   378, -2112, 11509,  8182, -1888,   318,    -2,
    -1,   378, -2113, 11439,  8262, -1899,   321,    -2,
    -1,   378, -2115, 11369,  8341, -1909,   323,    -2,
    -1,   378, -2116, 11298,  8420, -1920,   326,    -2,
    -1,   378, -2116, 11227,  8499, -1930,   328,    -1,
    -1,   378, -2116, 11156,  8578, -1940,   331,    -1,
    -1,   378, -2116, 11084,  8656, -1949,   333,    -1,
    -1,   377, -2116, 11012,  8735, -1959,   335,    -1,
    -1,   377, -2115, 10940,  8814, -1968,   337,    -1,
    -1,   377, -2114, 10867,  8892, -1977,   340,    -1,
    -1,   376, -2112, 10795,  8971, -1985,   342,    -1,
     0,   375, -2111, 10721,  9049, -1994,   344,    -1,
     0,   375, -2108, 10648,  9127, -2002,   346,     0,
     0,   374, -2106, 10574,  9205, -2010,   348,     0,
     0,   373, -2103, 10500,  9283, -2018,   350,     0,
     0,   372, -2100, 10426,  9360, -2025,   352,     0,
     0,   371, -2097, 10351,  9438, -2032,   354,     0,
     0,   370, -2093, 10276,  9515, -2039,   355,     0,
     0,   369, -2089, 10201,  9592, -2046,   357,     0,
     0,   367, -2084, 10126,  9669, -2052,   359,     0,
     0,   366, -2080, 10050,  9745, -2058,   360,     0,
     0,   365, -2075,  9974,  9822, -2064,   362,     0,
     0,   363, -2070,  9898,  9898, -2070,   363,     0,
     0,   362, -2064,  9822,  9974, -2075,   365,     0,
     0,   360, -2058,  9745, 10050, -2080,   366,     0,
     0,   359, -2052,  9669, 10126, -2084,   367,     0,
     0,   357, -2046,  9592, 10201, -2089,   369,     0,
     0,   355, -2039,  9515, 10276, -2093,   370,     0,
     0,   354, -2032,  9438, 10351, -2097,   371,     0,
     0,   352, -2025,  9360, 10426, -2100,   372,     0,
     0,   350, -2018,  9283, 10500, -2103,   373,     0,
     0,   348, -2010,  9205, 10574, -2106,   374,     0,
     0,   346, -2002,  9127, 10648, -2108,   375,     0,
    -1,   344, -1994,  9049, 10721, -2111,   375,     0,
    -1,   342, -1985,  8971, 10795, -2112,   376,    -1,
    -1,   340, -1977,  8892, 10867, -2114,   377,    -1,
    -1,   337, -1968,  8814, 10940, -2115,   377,    -1,
    -1,   335, -1959,  8735, 11012, -2116,   377,    -1,
    -1,   333, -1949,  8656, 11084, -2116,   378,    -1,
    -1,   331, -1940,  8578, 11156, -2116,   378,    -1,
    -1,   328, -1930,  8499, 11227, -2116,   378,    -1,
    -2,   326, -1920,  8420, 11298, -2116,   378,    -1,
    -2,   323, -1909,  8341, 11369, -2115,   378,    -1,
    -2,   321, -1899,  8262, 11439, -2113,   378,    -1,
    -2,   318, -1888,  8182, 11509, -2112,   378,    -2,
    -2,   316, -1877,  8103, 11578, -2110,   378,    -2,
    -2,   313, -1866,  8024, 11647, -2107,   377,    -2,
    -3,   311, -1855,  7944, 11716, -2104,   377,    -2,
    -3,   308, -1844,  7865, 11785, -2101,   376,    -2,
    -3,   305, -1832,  7785, 11852, -2098,   376,    -2,
    -3,   303, -1820,  7706, 11920, -2094,   375,    -2,
    -4,   300, -1808,  7626, 11987, -2089,   374,    -3,
    -4,   297, -1796,  7547, 12054, -2084,   373,    -3,
    -4,   294, -1784,  7467, 12120, -2079,   372,    -3,
    -4,   291, -1771,  7388, 12186, -2074,   371,    -3,
    -5,   289, -1758,  7308, 12251, -2068,   370,    -3,
    -5,   286, -1745,  7229, 12316, -2062,   369,    -3,
    -5,   283, -1732,  7149, 12381, -2055,   367,    -3,
    -6,   280, -1719,  7070, 12445, -2048,   366,    -4,
    -6,   277, -1706,  6990, 12509, -2040,   364,    -4,
    -6,   274, -1693,  6911, 12572, -2032,   362,    -4,
    -7,   271, -1679,  6831, 12634, -2024,   360,    -4,
    -7,   268, -1665,  6752, 12696, -2015,   358,    -4,
    -7,   265, -1651,  6673, 12758, -2005,   356,    -4,
    -8,   262, -1637,  6594, 12819, -1996,   354,    -4,
    -8,   259, -1623,  6514, 12880, -1986,   352,    -4,
    -8,   256, -1609,  6435, 12940, -1975,   349,    -5,
    -9,   253, -1595,  6356, 13000, -1964,   347,    -5,
    -9,   250, -1580,  6277, 13059, -1952,   344,    -5,
   -10,   247, -1566,  6199, 13118, -1940,   341,    -5,
   -10,   244, -1551,  6120, 13176, -1928,   338,    -5,
   -10,   241, -1536,  6041, 13233, -1915,   335,    -5,
   -11,   238, -1521,  5963, 13290, -1902,   332,    -5,
   -11,   235, -1506,  5885, 13347, -1888,   329,    -5,
   -12,   232, -1491,  5806, 13402, -1874,   326,    -5,
   -12,   229, -1476,  5728, 13458, -1859,   322,    -5,
   -13,   225, -1461,  5651, 13512, -1844,   319,    -5,
   -13,   222, -1445,  5573, 13567, -1829,   315,    -5,
   -13,   219, -1430,  5495, 13620, -1813,   311,    -6,
   -14,   216, -1414,  5418, 13673, -1796,   307,    -6,
   -14,   213, -1399,  5340, 13726, -1779,   303,    -6,
   -15,   210, -1383,  5263, 13777, -1762,   299,    -6,
   -15,   207, -1368,  5186, 13829, -1744,   294,    -6,
   -16,   204, -1352,  5110, 13879, -1725,   290,    -6,
   -16,   201, -1336,  5033, 13929, -1706,   285,    -6,
   -17,   198, -1320,  4957, 13978, -1687,   280,    -6,
   -17,   195, -1304,  4881, 14027, -1667,   276,    -5,
   -18,   192, -1288,  4805, 14075, -1647,   271,    -5,
   -18,   189, -1272,  4729, 14123, -1626,   265,    -5,
   -19,   186, -1256,  4653, 14169, -1604,   260,    -5,
   -19,   183, -1240,  4578, 14216, -1583,   255,    -5,
   -20,   180, -1224,  4503, 14261, -1560,   249,    -5,
   -20,   177, -1208,  4428, 14306, -1537,   244,    -5,
   -21,   174, -1192,  4354, 14350, -1514,   238,    -5,
   -21,   171, -1175,  4279, 14394, -1490,   232,    -5,
   -22,   168, -1159,  4205, 14437, -1466,   226,    -4,
   -22,   165, -1143,  4131, 14479, -1441,   220,    -4,
   -22,   162, -1127,  4058, 14520, -1416,   213,    -4,
   -23,   159, -1110,  3985, 14561, -1390,   207,    -4,
   -23,   156, -1094,  3912, 14601, -1363,   200,    -4,
   -24,   153, -1078,  3839, 14640, -1337,   193,    -3,
   -24,   150, -1062,  3766, 14679, -1309,   187,    -3,
   -25,   147, -1045,  3694, 14717, -1281,   179,    -3,
   -25,   144, -1029,  3622, 14754, -1253,   172,    -3,
   -26,   142, -1013,  3551, 14791, -1224,   165,    -2,
   -26,   139,  -996,  3480, 14827, -1194,   158,    -2,
   -27,   136,  -980,  3409, 14862, -1164,   150,    -1,
   -27,   133,  -964,  3338, 14896, -1134,   142,    -1,
   -28,   131,  -948,  3268, 14930, -1103,   135,    -1,
   -28,   128,  -931,  3198, 14963, -1071,   127,     0,
   -29,   125,  -915,  3128, 14995, -1039,   118,     0,
   -29,   122,  -899,  3059, 15027, -1007,   110,     1,
   -29,   120,  -883,  2990, 15057,  -974,   102,     1,
   -30,   117,  -867,  2921, 15087,  -940,    93,     2,
   -30,   115,  -851,  2853, 15117,  -906,    85,     2,
   -31,   112,  -835,  2785, 15145,  -871,    76,     3,
   -31,   109,  -819,  2718, 15173,  -836,    67,     3,
   -32,   107,  -803,  2651, 15200,  -801,    58,     4,
   -32,   104,  -787,  2584, 15226,  -764,    49,     5,
   -32,   102,  -771,  2517, 15251,  -728,    39,     5,
   -33,    99,  -755,  2451, 15276,  -690,    30,     6,
   -33,    97,  -740,  2386, 15300,  -653,    20,     7,
   -33,    95,  -724,  2321, 15323,  -614,    10,     7,
   -34,    92,  -708,  2256, 15345,  -576,     1,     8,
   -34,    90,  -693,  2191, 15366,  -536,    -9,     9,
   -34,    88,  -677,  2127, 15387,  -496,   -20,    10,
   -35,    85,  -662,  2063, 15407,  -456,   -30,    11,
   -35,    83,  -646,  2000, 15426,  -415,   -40,    11,
   -35,    81,  -631,  1937, 15445,  -374,   -51,    12,
   -36,    79,  -616,  1875, 15462,  -332,   -62,    13,
   -36,    76,  -600,  1813, 15479,  -289,   -72,    14,
   -36,    74,  -585,  1751, 15495,  -247,   -83,    15,
   -36,    72,  -570,  1690, 15510,  -203,   -94,    16,
   -37,    70,  -555,  1629, 15524,  -159,  -106,    17,
   -37,    68,  -540,  1569, 15538,  -115,  -117,    18,
   -37,    66,  -526,  1509, 15550,   -70,  -128,    19,
   -37,    64,  -511,  1450, 15562,   -24,  -140,    21,
   -37,    62,  -496,  1391, 15573,    22,  -152,    22,
   -38,    60,  -482,  1332, 15583,    68,  -164,    23,
   -38,    58,  -467,  1274, 15593,   115,  -175,    24,
   -38,    56,  -453,  1216, 15601,   163,  -188,    25,
   -38,    54,  -439,  1159, 15609,   211,  -200,    27,
   -38,    53,  -425,  1103, 15616,   259,  -212,    28,
   -38,    51,  -410,  1046, 15622,   309,  -224,    29,
   -38,    49,  -396,   990, 15628,   358,  -237,    31,
   -38,    47,  -383,   935, 15632,   408,  -250,    32,
   -38,    46,  -369,   880, 15636,   459,  -263,    33,
   -38,    44,  -355,   826, 15639,   510,  -275,    35,
   -38,    42,  -342,   772, 15641,   561,  -288,    36,
   -38,    41,  -328,   718, 15642,   613,  -302,    38,
];
