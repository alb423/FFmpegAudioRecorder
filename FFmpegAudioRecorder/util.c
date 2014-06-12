#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <netinet/in.h>
#include <net/if.h>
#include <netdb.h>
#include <arpa/inet.h>

#include <ifaddrs.h>

#include "util.h"

char gpLocalAddr[NET_MAX_INTERFACE][32]={{0}};
char gpMacAddr[NET_MAX_INTERFACE][32]={{0}};
#define LOCAL_ADDR gpLocalAddr//"192.168.2.102"

static int _gIsMulticast = 0;

struct sockaddr_in gMSockAddr;

char * CopyString(char *pSrc)
{
    int vLen = 0;
    char *pDst = NULL;
    
    if(!pSrc) return NULL;
    
    vLen = strlen(pSrc);
    pDst = malloc(vLen+1);
    memcpy(pDst, pSrc, vLen);
    
    return pDst;
}

void SetMulticastFlag(int bFlag)
{
   _gIsMulticast = bFlag;
}

int GetMulticastFlag()
{
   return _gIsMulticast;
}

char * getMyMacAddress(void)
{
    return NULL;//CopyString(gpMacAddr[0]);
}

// Utilities of Network
char * getMyIpString(char *pIfName)
{
   int i = 0;
   if(pIfName==NULL)
   return NULL;
   
   for(i=0;i<NET_MAX_INTERFACE;i++)
   {
      if(strncmp("en1", pIfName, 3)==0)
      {
         return CopyString(gpLocalAddr[1]);
      } 
   }
   return CopyString(gpLocalAddr[0]);
}


char * initMyIpString(void)
{
   int vInterfaceCount=0;
   char pInterface[128]={0};
   struct ifaddrs * ifAddrStruct=NULL;
   struct ifaddrs * ifa=NULL;
   void * tmpAddrPtr=NULL;
   
   getifaddrs(&ifAddrStruct);
   
   for (ifa = ifAddrStruct; ifa != NULL; ifa = ifa->ifa_next) 
   {
      if (ifa ->ifa_addr->sa_family==AF_INET) 
      {   
         // check it is IP4
         // is a valid IP4 Address
         char addressBuffer[INET_ADDRSTRLEN];
         tmpAddrPtr=&((struct sockaddr_in *)ifa->ifa_addr)->sin_addr;
         
         inet_ntop(AF_INET, tmpAddrPtr, addressBuffer, INET_ADDRSTRLEN);
         //DBG("%s IP Address %s\n", ifa->ifa_name, addressBuffer); 
         if(strncmp(ifa->ifa_name, INTERFACE_NAME_1, 2)==0)
         {
            // Note: you may set local address for different interface. For example:eth0, eth1
            memcpy(gpLocalAddr[vInterfaceCount], addressBuffer, strlen(addressBuffer));
            memset(pInterface, 0 ,128);
            memcpy(pInterface, ifa->ifa_name, strlen(ifa->ifa_name));
            
            #ifdef __APPLE__
               // I don't know how to get Mac Address in Mac OS
               sprintf(gpMacAddr[0], "10ddb1acc6ee");
               sprintf(gpMacAddr[1], "4c8d79eaee74");
            #else            
            {
               // For linux system
               int sock;
               struct ifreq ifr;
               
               sock = socket(AF_INET, SOCK_DGRAM, 0);
               ifr.ifr_addr.sa_family = AF_INET;
               
               strncpy(ifr.ifr_name, pInterface, IFNAMSIZ-1);
               
               ioctl(sock, SIOCGIFHWADDR, &ifr);
               
               close(sock);
               
               sprintf(gpMacAddr[vInterfaceCount], "%.2x%.2x%.2x%.2x%.2x%.2x", 
               (unsigned char)ifr.ifr_hwaddr.sa_data[0],
               (unsigned char)ifr.ifr_hwaddr.sa_data[1],
               (unsigned char)ifr.ifr_hwaddr.sa_data[2],
               (unsigned char)ifr.ifr_hwaddr.sa_data[3],
               (unsigned char)ifr.ifr_hwaddr.sa_data[4],
               (unsigned char)ifr.ifr_hwaddr.sa_data[5]);
               //DBG("MAC %s\n", gpMacAddr[vInterfaceCount]); 
            }
            #endif
            vInterfaceCount++;
         } 
      } 
      else if (ifa->ifa_addr->sa_family==AF_INET6) 
      {   
         // check it is IP6
         // is a valid IP6 Address
         tmpAddrPtr=&((struct sockaddr_in6 *)ifa->ifa_addr)->sin6_addr;
         char addressBuffer[INET6_ADDRSTRLEN];
         inet_ntop(AF_INET6, tmpAddrPtr, addressBuffer, INET6_ADDRSTRLEN);
         //DBG("%s IP Address %s\n", ifa->ifa_name, addressBuffer); 
      }         
   }
   
   
   DBG("gpLocalAddr is set to %s, MAC is %s\n\n", gpLocalAddr[0], gpMacAddr[0]);    
   if (ifAddrStruct!=NULL) freeifaddrs(ifAddrStruct);
   return gpLocalAddr[0];
}

int CreateUnicastClient(struct sockaddr_in *pSockAddr, int port)
{
   // http://www.tenouk.com/Module41c.html
   int sd=-1;
   
   struct timeval timeout;
   timeout.tv_sec  = 10;
   timeout.tv_usec = 0;
   
   sd = socket(AF_INET, SOCK_DGRAM, 0);
   if(sd < 0)
   {
      perror("Opening datagram socket error");
      exit(1);
   }
   else
      DBG("Opening the datagram socket %d...OK.\n", sd);
   
   if(setsockopt(sd, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout, sizeof(timeout)) < 0)
   {
      DBG("setsockopt...error.\n");
   }
   
#if 0
   int reuse=1;
   struct sockaddr_in localSock;   
   if(setsockopt(sd, SOL_SOCKET, SO_REUSEADDR, (char *)&reuse, sizeof(reuse)) < 0)
   {
      perror("Setting SO_REUSEADDR error");
      close(sd);
      exit(1);
   }
   else
      DBG("Setting SO_REUSEADDR...OK.\n");
         
   // The host may have many interface
   // If needed, we may create the socket to bind the interface that data was sent.
   localSock.sin_family = AF_INET;
   localSock.sin_port = htons(MULTICAST_PORT);
   //localSock.sin_addr.s_addr = htonl(INADDR_ANY);
   localSock.sin_addr.s_addr = inet_addr(gpLocalAddr[0]);
   if(bind(sd, (struct sockaddr*)&localSock, sizeof(localSock)))
   {
      perror("Binding datagram socket error");
      close(sd);
      exit(1);
   }
   else
      DBG("Binding port:%d socket...OK.\n",port);
#endif
   
   return sd;
}


int CreateMulticastClient(char *pAddress, int port)
{
   // http://www.tenouk.com/Module41c.html
   struct in_addr localInterface;
   int i, sd=-1;
   
   struct ip_mreq group;
   struct timeval timeout;
   timeout.tv_sec  = 10;
   timeout.tv_usec = 0;
   
   if(!pAddress)
      return -1;
   if(strlen(pAddress)==0)
      return -1;
   
   sd = socket(AF_INET, SOCK_DGRAM, 0);
   if(sd < 0)
   {
      perror("Opening datagram socket error");
      exit(1);
   }
   else
      DBG("Opening multicast client socket %d for ip %s...OK.\n", sd, pAddress);
   
   if(setsockopt(sd, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout, sizeof(timeout)) < 0)
   {
      DBG("setsockopt...error.\n");
   }

    int reuse=1;
    if(setsockopt(sd, SOL_SOCKET, SO_REUSEADDR, (char *)&reuse, sizeof(reuse)) < 0)
    {
        perror("Setting SO_REUSEADDR error");
        close(sd);
        exit(1);
    }
    else
        DBG("Setting SO_REUSEADDR...OK.\n");
   
   unsigned char ttl, loop;
   int ttlSize, loopSize;
   loop = 1;/*0;*/ loopSize = sizeof(loop);
   ttl = 5; ttlSize = sizeof(ttl);
   setsockopt(sd, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, loopSize);
   setsockopt(sd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, ttlSize);
   getsockopt(sd, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, (socklen_t *)&loopSize);
   getsockopt(sd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, (socklen_t *)&ttlSize);
   
   memset((char *) &gMSockAddr, 0, sizeof(gMSockAddr));
   gMSockAddr.sin_family = AF_INET;
   gMSockAddr.sin_addr.s_addr = inet_addr(MULTICAST_ADDR);
   gMSockAddr.sin_port = htons(port);
   
   localInterface.s_addr = inet_addr(pAddress);
   
   if(setsockopt(sd, IPPROTO_IP, IP_MULTICAST_IF, (char *)&localInterface.s_addr, sizeof(localInterface)) < 0)
   {
      perror("Setting local interface error");
      exit(1);
   }
   else
      DBG("Setting the local interface...OK\n");    
   

   for(i=0;i<NET_MAX_INTERFACE;i++)
   {
      group.imr_multiaddr.s_addr = inet_addr(pAddress);
      if(strlen(gpLocalAddr[i])!=0)
      {
         group.imr_interface.s_addr = inet_addr(gpLocalAddr[i]);
         // In MAC, if we set INADDR_ANY, it will set only the 1st network interface
         // group.imr_interface.s_addr = INADDR_ANY;
         if(setsockopt(sd, IPPROTO_IP, IP_ADD_MEMBERSHIP, (char *)&group, sizeof(group)) < 0)
         {
            perror("setsockopt IP_ADD_MEMBERSHIP error");
            // This error may happened if some process had already do IP_ADD_MEMBERSHIP
            // This error can be omited
            //close(sd);
            //exit(1);
         }
         else
         {
            DBG("setsockopt IP_ADD_MEMBERSHIP for %s ...OK.\n", gpLocalAddr[i]);
         }
      }
   }
   
   
   return sd;
}

int CreateMulticastServer(char *pAddress, int port)
{
   struct ip_mreq group;
   struct sockaddr_in localSock;
   int i, sd;
   int reuse = 1;
   
   sd = socket(AF_INET, SOCK_DGRAM, 0);

   if(sd < 0)
   {
      perror("Opening datagram socket error");
      exit(1);
   }
   else
      DBG("Opening multicast server socket %d for ip %s...OK.\n",sd, pAddress);
   

   if(setsockopt(sd, SOL_SOCKET, SO_REUSEADDR, (char *)&reuse, sizeof(reuse)) < 0)
   {
      perror("Setting SO_REUSEADDR error");
      close(sd);
      exit(1);
   }
   else
      DBG("Setting SO_REUSEADDR...OK.\n");

   
   memset((char *) &localSock, 0, sizeof(localSock));
   localSock.sin_family = AF_INET;
   localSock.sin_port = htons(port);
   localSock.sin_addr.s_addr = INADDR_ANY;
   
   int opt = 1;
   if(setsockopt(sd, IPPROTO_IP, IP_PKTINFO, &opt, sizeof(opt)) < 0)
      printf("set IP_PKTINFO error\n");
       
   for(i=0;i<NET_MAX_INTERFACE;i++)
   {
      group.imr_multiaddr.s_addr = inet_addr(pAddress);
      if(strlen(gpLocalAddr[i])!=0)
      {
         group.imr_interface.s_addr = inet_addr(gpLocalAddr[i]); 
         // In MAC, if we set INADDR_ANY, it will set only the 1st network interface
         // group.imr_interface.s_addr = INADDR_ANY;
         if(setsockopt(sd, IPPROTO_IP, IP_ADD_MEMBERSHIP, (char *)&group, sizeof(group)) < 0)
         {
            perror("setsockopt IP_ADD_MEMBERSHIP error");
            // This error may happened if some process had already do IP_ADD_MEMBERSHIP
            // This error can be omited
            //close(sd);
            //exit(1);
         }
         else
         {
            DBG("setsockopt IP_ADD_MEMBERSHIP for %s ...OK.\n", gpLocalAddr[i]);
         }
      }
   }
               
   if(bind(sd, (struct sockaddr*)&localSock, sizeof(localSock)))
   {
      perror("Binding datagram socket error");
      close(sd);
      exit(1);
   }
   else
      DBG("Binding port:%d socket...OK.\n",port);
   
   return sd;
}


int CreateUnicastServer(char *pAddress, int vPort)
{
   int sd;
   struct sockaddr_in localSock;   
   
   if(!pAddress)
      return -1;
   if(strlen(pAddress)==0)
      return -1;
         
   sd = socket(AF_INET, SOCK_DGRAM, 0);
   if(sd < 0)
   {
      perror("Opening datagram socket error");
      exit(1);
   }
   else
      DBG("Opening unicast server socket %d for ip %s...OK.\n",sd, pAddress);
   
   {
      int reuse = 1;
      if(setsockopt(sd, SOL_SOCKET, SO_REUSEADDR, (char *)&reuse, sizeof(reuse)) < 0)
      {
         perror("Setting SO_REUSEADDR error");
         close(sd);
         exit(1);
      }
      else
         DBG("Setting SO_REUSEADDR...OK.\n");
   }
   
   memset((char *) &localSock, 0, sizeof(localSock));
   localSock.sin_family = AF_INET;
   localSock.sin_port = htons(vPort);
   localSock.sin_addr.s_addr = inet_addr(pAddress);
   
   if(bind(sd, (struct sockaddr*)&localSock, sizeof(localSock)))
   {
      perror("Binding datagram socket error");
      close(sd);
      exit(1);
   }
   else
      DBG("Binding datagram socket...OK.\n");
   
   return sd;
}


       
// Random function
void InitMyRandom(char *myipaddr)
{
   unsigned int ourAddress;
   struct timeval timeNow;
   
   ourAddress = ntohl(inet_addr(myipaddr));
   gettimeofday(&timeNow, NULL);
   
   unsigned int seed = ourAddress^timeNow.tv_sec^timeNow.tv_usec;
     
   srandom(seed);
}

long our_random() 
{
   return random();
}

unsigned int our_random16()
{
   long random1 = our_random();
   return (unsigned int)(random1&0xffff);
}


unsigned int our_random32() 
{  
   long random1 = our_random();
   long random2 = our_random();
   
   return (unsigned int)((random2<<31) | random1);
}
              
void UuidGen(char *uuidbuf)
{
   sprintf(uuidbuf, "%08x-%04x-%04x-%04x-%08x%04x",our_random32(), our_random16(),our_random16(),our_random16(),our_random32(), our_random16());    
}     


void noprintf(char *format, ...)
{
   ;
}        
