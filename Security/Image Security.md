# Imaj Güvenlişi

## Deterministik docker  imaj etiketlerini kullanın

* Genel imaj takma adları yerine SHA256 hash olanları veya deterministik imaj  sürümlerini kullanın.
* FROM maven:3.6.3-jdk-11-slim@sha256:68ce1cd457891f48d1e137c7d6a4493f60843e84c9e2634e3df1d3d5b381d36c
* İşletim sistemlerinin bir sürümlerini aşaşıdaki gibi alarak deterministik bir sürüm alabiliriz.

## Yalnızca ihtiyacınız olanı kurun

Bir JDK'ya, Java koduna veya Maven ve Gradle gibi bir derleme aracına ihtiyacınız yoktur. Bunun yerine,

        Sadece WAR ya da Jar dosyasınızı kopyalayın.
        JRE ürününü veya imajnını kullanın.

Uygulamaların koşacaşı imajı bu şekilde üretirsek sadece jre kurmuş oluyoruz. Ayrıca boyut 120MB azalıyor.



## Java Docker imajlarınızdaki güvenlik açıklarını bulun ve düzeltin.

* https://snyk.io/product/open-source-security-management/
* trivy - https://gitlab.com/haynes/trivy-airgapped


```bash
trivy image --exit-code 1 --severity HIGH,CRITICAL $IMAGE_NAME

```
## Multistage buildler kullanın

Eşer build işlemlerini konteynır içinde yapıyorsanız 2 imajın ayrı olması gerekir.

```Dockerfile

# ---- Base Node ----
FROM node:14-slim AS base
WORKDIR /app
COPY package*.json ./

# ---- Dependencies ----
FROM base AS dependencies
# Install production dependencies
RUN npm ci --only=production

# ---- Build ----
FROM base AS build
# Install all dependencies and build the project
COPY . .
RUN npm ci && npm run build

# ---- Release ----
FROM node:14-slim AS release
# Create app directory
WORKDIR /app

# Create a non-root user: nodeuser
RUN addgroup --system nodegroup && adduser --system --group nodegroup
USER nodegroup

# Copy production dependencies
COPY --from=dependencies /app/node_modules ./node_modules
# Copy app sources
COPY --from=build /app .

# Expose the application on port 3000
EXPOSE 3000

# Start the application
CMD ["npm", "start"]


```

```Dockerfile

# ---- Base Python ----
FROM python:3.8-slim AS base
WORKDIR /app
COPY requirements.txt .

# ---- Dependencies ----
FROM base AS dependencies
RUN pip install --no-cache-dir -r requirements.txt

# ---- Copy Files/Build ----
FROM dependencies AS build
WORKDIR /app
COPY . /app

# ---- Release ----
FROM base AS release
WORKDIR /app

# Create non-root user
RUN useradd -m myuser
USER myuser

# Copy python scripts and compiled files
COPY --from=build /app .

# Command to run the application
CMD ["python", "app.py"]

```

```Dockerfile

# ---- Base Maven ----
FROM maven:3.8.2-openjdk-11-slim AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline

# ---- Dependencies ----
COPY src/ /app/src/
RUN mvn package

# ---- Release ----
FROM openjdk:11-jre-slim AS release
WORKDIR /app

# Create non-root user
RUN addgroup --system javauser && adduser --system --group javauser
USER javauser

# Copy application JAR and other dependencies
COPY --from=build /app/target/my-app.jar .

# Command to run the application
CMD ["java", "-jar", "my-app.jar"]

```

## Properly handle events to safely terminate a Java application (stability)

pid-1 de çalışacak şekilde kullanmayın.

CMD ÇojavaÇ” Ço-jarÇ” Çoapplication.jarÇ”
CMD Çostart-app.shÇ”


Lite bir init desteşi kullanın. Bu sayede Java prosesine saşlıklı bir şekilde sinyal gönderebilirsiniz. Java processi signalleri handle edemedişi için öldürme isteklerine cevap vermeyebiliyor bazı durumlarda. Container ölemiyor. Ama dumb-init gibi bir araç kernelden gelen sinyalleri işleyebildişi için java processini öldürüyor ve sonra da kendisi de ölüyor.


CMD Çodumb-initÇ” ÇojavaÇ” Ço-jarÇ” Çoapplication.jarÇ”

https://github.com/Yelp/dumb-init

Çalışan bir Java uygulamasını ani bir şekilde sonlandırmak önlemek, aktif canlı başlantıları da durdurur.  Kapatmak için uygulama içinde kapatma mesajları gönderin. 

Runtime.getRuntime().addShutdownHook
(yourShutdownThread);

## Java appleri root yetkisi ile deşil standart kullanıcı ile çalıştırın.


## .dockerignore kullanın

build sırasındaki ve öncesinde oluşturulan veya oluşan dosyalar yanlışlıkla imajla beraber gitmez.
Konteynırda olduşunu anlayan Java kullanın

##  Eski JVM sürümleri Docker memory and CPU ayarlarına uymaz.
Java 10+ veya Java 8 update 191+ üzeri kullanın.



## jib kullanımı

```
*********
   <plugin>     
            <groupId>com.google.cloud.tools</groupId>
            <artifactId>jib-maven-plugin</artifactId>
            <version>3.4.0</version>
            <configuration>
              <to>
                <image>spring-with-root</image>
              </to>
            </configuration>
          </plugin>
******** 

*********
   <plugin>     
            <groupId>com.google.cloud.tools</groupId>
            <artifactId>jib-maven-plugin</artifactId>
            <version>3.4.0</version>
            <configuration>
              <to>
                <image>spring-with-no-root</image>
              </to>
              nginx-container
                <user>5005:5005</user>
            </container>
            </configuration>
          </plugin>
******** 


mvn compile jib:build

mvn compile jib:dockerBuild

```

## node
```Dockerfile
# ---- Base Node ----
FROM node:14-slim AS base
WORKDIR /app
COPY package*.json ./

# ---- Dependencies ----
FROM base AS dependencies
# Install production dependencies
RUN npm ci --only=production

# ---- Build ----
FROM base AS build
# Install all dependencies and build the project
COPY . .
RUN npm ci && npm run build

# ---- Release ----
FROM node:14-slim AS release
# Create app directory
WORKDIR /app

# Create a non-root user: nodeuser
RUN addgroup --system nodegroup && adduser --system --group nodegroup
USER nodegroup

# Copy production dependencies
COPY --from=dependencies /app/node_modules ./node_modules
# Copy app sources
COPY --from=build /app .

# Expose the application on port 3000
EXPOSE 3000

# Start the application
CMD ["npm", "start"]

```

## python
```Dockerfile
# ---- Base Python ----
FROM python:3.8-slim AS base
WORKDIR /app
COPY requirements.txt .

# ---- Dependencies ----
FROM base AS dependencies
RUN pip install --no-cache-dir -r requirements.txt

# ---- Copy Files/Build ----
FROM dependencies AS build
WORKDIR /app
COPY . /app

# ---- Release ----
FROM base AS release
WORKDIR /app

# Create non-root user
RUN useradd -m myuser
USER myuser

# Copy python scripts and compiled files
COPY --from=build /app .

# Command to run the application
CMD ["python", "app.py"]

```


## maven
```Dockerfile
# ---- Base Maven ----
FROM maven:3.8.2-openjdk-11-slim AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline

# ---- Dependencies ----
COPY src/ /app/src/
RUN mvn package

# ---- Release ----
FROM openjdk:11-jre-slim AS release
WORKDIR /app

# Create non-root user
RUN addgroup --system javauser && adduser --system --group javauser
USER javauser

# Copy application JAR and other dependencies
COPY --from=build /app/target/my-app.jar .

# Command to run the application
CMD ["java", "-jar", "my-app.jar"]


```

#### Kaynaklar


https://snyk.io/blog/docker-for-java-developers/

https://snyk.io/blog/best-practices-to-build-java-containers-with-docker/

https://www.tutorialworks.com/docker-java-best-practices/

https://akobor.me/posts/heap-size-and-resource-limits-in-kubernetes-for-jvm-applications (kaynaklar ve xms açısından yaklaşmış)

https://medium.com/marionete/managing-java-heap-size-in-kubernetes-3807159e2438

https://labs.bishopfox.com/tech-blog/bad-pods-kubernetes-pod-privilege-escalation (pod güvenlişi ile ilgili geniş bir çalışma) ***

https://infosecwriteups.com/kubernetes-container-escape-with-hostpath-mounts-d1b86bd2fa3
