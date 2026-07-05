FROM golang:1.26.4-alpine3.23 AS build

WORKDIR /app

COPY go.mod ./

RUN go mod download 

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o app .

FROM gcr.io/distroless/base-debian13 AS runtime

COPY --from=build /app/app /bin/app

EXPOSE 8090

ENTRYPOINT ["/bin/app"]