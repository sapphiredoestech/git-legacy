/*
 * File: priority2.c
 *
 * Test Synopsis:
 * - Test thread priority setting after creation.
 *
 * Test Method (Validation or Falsification):
 * - 
 *
 * Requirements Tested:
 * -
 *
 * Features Tested:
 * -
 *
 * Cases Tested:
 * -
 *
 * Description:
 * -
 *
 * Environment:
 * -
 *
 * Input:
 * - None.
 *
 * Output:
 * - File name, Line number, and failed expression on failure.
 * - No output on success.
 *
 * Assumptions:
 * -
 *
 * Pass Criteria:
 * - Process returns zero exit status.
 *
 * Fail Criteria:
 * - Process returns non-zero exit status.
 */

#include "test.h"

pthread_mutex_t startMx = PTHREAD_MUTEX_INITIALIZER;

void * func(void * arg)
{
  int policy;
  struct sched_param param;

  assert(pthread_mutex_lock(&startMx) == 0);
  assert(pthread_getschedparam(pthread_self(), &policy, &param) == 0);
  assert(pthread_mutex_unlock(&startMx) == 0);
  assert(policy == SCHED_FIFO);
  return (void *) (size_t)param.sched_priority;
}

// Windows only supports 7 thread priority levels, which we map onto the 32
// required by POSIX.  The exact mapping also depends on the overall process
// priority class. So only a subset of values will be returned exactly by
// pthread_getschedparam() after pthread_setschedparam().
int doable_pri(int pri)
{
  switch (GetPriorityClass(GetCurrentProcess()))
    {
    case BELOW_NORMAL_PRIORITY_CLASS:
      return (pri == 2) || (pri ==  8) || (pri == 10) || (pri == 12) || (pri == 14) || (pri == 16) || (pri == 30);
    case NORMAL_PRIORITY_CLASS:
      return (pri == 2) || (pri == 12) || (pri == 14) || (pri == 16) || (pri == 18) || (pri == 20) || (pri == 30);
    }

  return TRUE;
}

int
main()
{
  pthread_t t;
  void * result = NULL;
  struct sched_param param;
  int maxPrio = sched_get_priority_max(SCHED_FIFO);
  int minPrio = sched_get_priority_min(SCHED_FIFO);

  for (param.sched_priority = minPrio;
       param.sched_priority <= maxPrio;
       param.sched_priority++)
    {
      assert(pthread_mutex_lock(&startMx) == 0);
      assert(pthread_create(&t, NULL, func, NULL) == 0);
      assert(pthread_setschedparam(t, SCHED_FIFO, &param) == 0);
      assert(pthread_mutex_unlock(&startMx) == 0);
      pthread_join(t, &result);
      if (doable_pri(param.sched_priority))
	assert((int)(size_t)result == param.sched_priority);
    }

  return 0;
}
