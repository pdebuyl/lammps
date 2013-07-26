/* ----------------------------------------------------------------------
   LAMMPS - Large-scale Atomic/Molecular Massively Parallel Simulator
   http://lammps.sandia.gov, Sandia National Laboratories
   Steve Plimpton, sjplimp@sandia.gov

   Copyright (2003) Sandia Corporation.  Under the terms of Contract
   DE-AC04-94AL85000 with Sandia Corporation, the U.S. Government retains
   certain rights in this software.  This software is distributed under
   the GNU General Public License.

   See the README file in the top-level LAMMPS directory.
------------------------------------------------------------------------- */

#include "mpi.h"
#include "timer.h"
#include "comm.h"
#include "error.h"
#include "memory.h"

#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/time.h>
#include <sys/resource.h>
#endif

using namespace LAMMPS_NS;

// Return the CPU time for the current process in seconds very
// much in the same way as MPI_Wtime() returns the wall time.

static double CPU_Time()
{
  double rv = 0.0;

#ifdef _WIN32

  // from MSD docs.
  FILETIME ct,et,kt,ut;
  union { FILETIME ft; uint64_t ui; } cpu;
  if (GetProcessTimes(GetCurrentProcess(),&ct,&et,&kt,&ut)) {
    cpu.ft = ut;
    rv = cpu.ui * 0.0000001;
  }

#else /* ! _WIN32 */

  struct rusage ru;
  if (getrusage(RUSAGE_SELF, &ru) == 0) {
    rv = (double) ru.ru_utime.tv_sec;
    rv += (double) ru.ru_utime.tv_usec * 0.000001;
  }

#endif /* ! _WIN32 */

  return rv;
}

/* ---------------------------------------------------------------------- */

Timer::Timer(LAMMPS *lmp) : Pointers(lmp)
{
  _level = NORMAL;
  _sync  = OFF;
}

/* ---------------------------------------------------------------------- */

void Timer::init()
{
  for (int i = 0; i < NUM_TIMER; i++) {
    cpu_array[i] = 0.0;
    wall_array[i] = 0.0;
  }
}

/* ---------------------------------------------------------------------- */

void Timer::_stamp(enum ttype which)
{
  double current_cpu=0.0, current_wall=0.0;

  if (_level > NORMAL) current_cpu = CPU_Time();
  current_wall = MPI_Wtime();

  if ((which > TOTAL) && (which < NUM_TIMER)) {
    cpu_array[which]  += current_cpu - previous_cpu;
    wall_array[which] += current_wall - previous_wall;
  }

  previous_cpu  = current_cpu;
  previous_wall = current_wall;

  if (_sync) {
    MPI_Barrier(world);
    if (_level > NORMAL) current_cpu = CPU_Time();
    current_wall = MPI_Wtime();

    cpu_array[SYNC]  += current_cpu - previous_cpu;
    wall_array[SYNC] += current_wall - previous_wall;
    previous_cpu  = current_cpu;
    previous_wall = current_wall;
  }
}

/* ---------------------------------------------------------------------- */

void Timer::barrier_start()
{
  double current_cpu=0.0, current_wall=0.0;

  MPI_Barrier(world);

  if (_level > NORMAL) current_cpu = CPU_Time();
  current_wall = MPI_Wtime();

  cpu_array[TOTAL]  = current_cpu;
  wall_array[TOTAL] = current_wall;
  previous_cpu  = current_cpu;
  previous_wall = current_wall;
}

/* ---------------------------------------------------------------------- */

void Timer::barrier_stop()
{
  double current_cpu=0.0, current_wall=0.0;

  MPI_Barrier(world);

  if (_level > NORMAL) current_cpu = CPU_Time();
  current_wall = MPI_Wtime();

  cpu_array[TOTAL]  = current_cpu - cpu_array[TOTAL];
  wall_array[TOTAL] = current_wall - wall_array[TOTAL];
}

/* ---------------------------------------------------------------------- */

double Timer::cpu(enum ttype which)
{
  double current_cpu = CPU_Time();
  return (current_cpu - cpu_array[which]);
}

/* ---------------------------------------------------------------------- */

double Timer::elapsed(enum ttype which)
{
  double current_wall = MPI_Wtime();
  return (current_wall - wall_array[which]);
}

/* ---------------------------------------------------------------------- */

void Timer::set_wall(enum ttype which, double newtime)
{
  wall_array[which] = newtime;
}

/* ----------------------------------------------------------------------
   modify parameters of the Timer class
------------------------------------------------------------------------- */
static const char *timer_style[] = { "off", "loop", "normal", "full" };
static const char *timer_mode[]  = { "nosync", "(dummy)", "sync" };
static const char  timer_fmt[]   = "New timer settings: style=%s  mode=%s\n";

void Timer::modify_params(int narg, char **arg)
{
  int iarg = 0;
  while (iarg < narg) {
    if (strcmp(arg[iarg],timer_style[OFF])           == 0) {
      _level = OFF;
    } else if (strcmp(arg[iarg],timer_style[LOOP]) == 0) {
      _level = LOOP;
    } else if (strcmp(arg[iarg],timer_style[NORMAL]) == 0) {
      _level = NORMAL;
    } else if (strcmp(arg[iarg],timer_style[FULL])   == 0) {
      _level = FULL;
    } else if (strcmp(arg[iarg],timer_mode[OFF])     == 0) {
      _sync  = OFF;
    } else if (strcmp(arg[iarg],timer_mode[NORMAL])  == 0) {
      _sync  = NORMAL;
    } else error->all(FLERR,"Illegal timers command");
    ++iarg;  
  }

  if (comm->me == 0) {
    if (screen)
      fprintf(screen,timer_fmt,timer_style[_level],timer_mode[_sync]);
    if (logfile)
      fprintf(logfile,timer_fmt,timer_style[_level],timer_mode[_sync]);
  }
}
