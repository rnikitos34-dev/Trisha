#ifndef Injector_h
#define Injector_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "libproc.h"
#import <mach/mach.h>
#import <mach/vm_map.h>
#import "proc_info.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/sysctl.h>
#include <mach/mach.h>

#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR

#include <sys/sysctl.h>
#include <sys/types.h>

/*
   * Use mach_vm_read_overwrite (avoids memory leaks).
   * vm_read is provided by system <mach/vm_map.h>.
*/

extern "C" {

extern kern_return_t
mach_vm_read_overwrite(
                       vm_map_t           target_task,
                       mach_vm_address_t  address,
                       mach_vm_size_t     size,
                       mach_vm_address_t  data,
                       mach_vm_size_t     *outsize);


extern kern_return_t
mach_vm_write(
              vm_map_t                          map,
              mach_vm_address_t                 address,
              pointer_t                         data,
              __unused mach_msg_type_number_t   size);

extern kern_return_t
mach_vm_region_recurse(
                       vm_map_t                 map,
                       mach_vm_address_t        *address,
                       mach_vm_size_t           *size,
                       uint32_t                 *depth,
                       vm_region_recurse_info_t info,
                       mach_msg_type_number_t   *infoCnt);

extern kern_return_t
processor_set_default(
                      host_t host,
                      processor_set_name_t *default_set
                      );

extern kern_return_t
host_processor_set_priv(
                        host_priv_t host_priv,
                        processor_set_name_t set_name,
                        processor_set_t *set
                        );

extern kern_return_t
processor_set_tasks(
                    processor_set_t processor_set,
                    task_array_t *task_list,
                    mach_msg_type_number_t *task_listCnt
                    );

extern kern_return_t pid_for_task(task_t task, int *pid);

extern kern_return_t
task_info(
          task_name_t target_task,
          task_flavor_t flavor,
          task_info_t task_info_out,
          mach_msg_type_number_t *task_info_outCnt
          );

extern host_name_port_t mach_host_self();

}

#else
#include <mach/mach_vm.h>
#include <mach-o/dyld_images.h>
#include <libproc.h>
#endif

mach_port_t get_task_for_PID(pid_t pid);
pid_t get_pid_by_name(const char *keyword);
task_t get_task_by_pid(pid_t pid);
/// Причина последней неудачи get_task_by_pid (для отладочного оверлея). Не NULL.
const char *get_task_last_error(void);
mach_vm_address_t get_image_base_address(mach_port_t task, const char *image_name);

template<typename T>
T Read(uintptr_t address, task_t task)
{
    T data = T();

    if (address <= 0 || address > 100000000000)
        return data;

    mach_vm_size_t out_size = 0;
    kern_return_t kr = mach_vm_read_overwrite(
        task,
        address,
        sizeof(T),
        (mach_vm_address_t)&data,
        &out_size
    );

    if (kr != KERN_SUCCESS || out_size != sizeof(T))
        return T();

    return data;
}

template<typename T>
void Write(uintptr_t address, T value, task_t task)
{
    if (address <= 0 || !task) return;
    mach_vm_write((vm_map_t)task, (mach_vm_address_t)address, (pointer_t)&value, (mach_msg_type_number_t)sizeof(T));
}


#endif /* Injector_h */
